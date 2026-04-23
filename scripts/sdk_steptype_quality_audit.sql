-- SDK step_type quality audit
-- Purpose: score generated tours using deterministic checks around step_type consistency.
-- Scope: tours created in the last 24 hours.

DROP TABLE IF EXISTS tmp_step_quality;
DROP TABLE IF EXISTS tmp_tour_quality;

CREATE TEMP TABLE tmp_step_quality AS
WITH recent_tours AS (
  SELECT
    gt.id AS tour_id,
    gt.name AS tour_name,
    gt.created_at,
    gt.target_url
  FROM guided_tours gt
  WHERE gt.created_at >= NOW() - INTERVAL '24 hours'
),
recent_steps AS (
  SELECT
    rt.tour_id,
    rt.tour_name,
    rt.created_at,
    rt.target_url,
    s.id AS step_id,
    s.order_index,
    s.title,
    s.content,
    s.target_selector,
    s.position,
    s.action,
    s.step_type,
    s.highlight_element,
    LOWER(COALESCE(s.title, '')) AS title_l,
    LOWER(COALESCE(s.content, '')) AS content_l,
    LOWER(COALESCE(s.target_selector, '')) AS selector_l,
    LOWER(COALESCE(s.title, '') || ' ' || COALESCE(s.content, '')) AS combined_l
  FROM recent_tours rt
  JOIN steps s ON s.tour_id = rt.tour_id
),
step_checks AS (
  SELECT
    rs.*,
    (rs.selector_l LIKE 'button%' OR rs.selector_l LIKE 'a[%') AS is_button_or_link,
    (rs.selector_l LIKE 'input%' OR rs.selector_l LIKE 'select%' OR rs.selector_l LIKE 'textarea%') AS is_form_control_selector,
    (rs.selector_l LIKE 'h1%' OR rs.selector_l LIKE 'h2%' OR rs.selector_l LIKE '[role="heading"]%') AS is_heading_selector,
    (rs.selector_l LIKE '%dialog%' OR rs.selector_l LIKE '%modal%' OR rs.selector_l LIKE '%drawer%' OR rs.combined_l ~ '(dialog|modal|drawer|fenetre)') AS has_modal_hint,
    (rs.selector_l LIKE 'video%' OR rs.selector_l LIKE 'iframe%' OR rs.combined_l ~ '(tutorial|tutoriel|video|walkthrough|youtube|vimeo|loom)') AS has_tutorial_hint,
    (rs.combined_l ~ '(checklist|to-do|todo|step by step|liste de taches|task list)') AS has_checklist_hint,
    (rs.combined_l ~ '(formulaire|form|champ|saisie|input|email|password|mot de passe|textarea|select)') AS has_form_hint,
    (rs.title_l ~ '(decouvrir|discovery|point d entree|point entree)') AS has_discovery_title,
    (rs.title_l ~ '(poursuivre|etape suivante|next|step suivante)') AS has_continue_title
  FROM recent_steps rs
),
scored_steps AS (
  SELECT
    sc.*,
    CASE WHEN sc.step_type IS NOT NULL THEN 1 ELSE 0 END AS r01_has_step_type,
    CASE WHEN sc.step_type::text IN ('tooltip','highlight','modal','form','tutorial','checklist') THEN 1 ELSE 0 END AS r02_step_type_allowed,
    CASE WHEN COALESCE(TRIM(sc.target_selector), '') <> '' THEN 1 ELSE 0 END AS r03_has_selector,
    CASE WHEN sc.position IS NOT NULL THEN 1 ELSE 0 END AS r04_has_position,
    CASE WHEN sc.action IS NOT NULL THEN 1 ELSE 0 END AS r05_has_action,

    CASE WHEN sc.step_type::text <> 'form' OR NOT sc.is_button_or_link THEN 1 ELSE 0 END AS r06_form_not_button_link,
    CASE WHEN sc.step_type::text <> 'form' OR sc.is_form_control_selector OR sc.has_form_hint THEN 1 ELSE 0 END AS r07_form_has_form_signal,

    CASE WHEN sc.step_type::text <> 'checklist' OR sc.has_checklist_hint THEN 1 ELSE 0 END AS r08_checklist_has_checklist_signal,
    CASE WHEN sc.step_type::text <> 'checklist' OR NOT sc.is_button_or_link THEN 1 ELSE 0 END AS r09_checklist_not_button_link,

    CASE WHEN sc.step_type::text <> 'tooltip' OR sc.action::text IN ('NEXT','HOVER') THEN 1 ELSE 0 END AS r10_tooltip_action_ok,
    CASE WHEN sc.step_type::text <> 'tooltip' OR sc.is_heading_selector OR sc.has_discovery_title THEN 1 ELSE 0 END AS r11_tooltip_discovery_signal,

    CASE WHEN sc.step_type::text <> 'highlight' OR sc.action::text IN ('CLICK','NEXT','COMPLETE','HOVER') THEN 1 ELSE 0 END AS r12_highlight_action_ok,
    CASE WHEN sc.step_type::text <> 'highlight' OR sc.selector_l ~ '^(button|a\[|input|select|textarea)' THEN 1 ELSE 0 END AS r13_highlight_actionable_signal,

    CASE WHEN sc.step_type::text <> 'modal' OR sc.has_modal_hint THEN 1 ELSE 0 END AS r14_modal_has_modal_signal,
    CASE WHEN sc.step_type::text <> 'tutorial' OR sc.has_tutorial_hint THEN 1 ELSE 0 END AS r15_tutorial_has_tutorial_signal,

    CASE WHEN sc.step_type::text NOT IN ('highlight','form') OR sc.highlight_element = TRUE THEN 1 ELSE 0 END AS r16_highlight_flag_for_highlight_form,
    CASE WHEN sc.step_type::text NOT IN ('tooltip','modal','tutorial','checklist') OR sc.highlight_element = FALSE THEN 1 ELSE 0 END AS r17_no_highlight_flag_for_non_highlight_types,

    CASE WHEN NOT sc.has_continue_title OR sc.step_type::text IN ('highlight','tooltip') THEN 1 ELSE 0 END AS r18_continue_title_prefers_highlight_tooltip,
    CASE WHEN NOT sc.has_discovery_title OR sc.step_type::text = 'tooltip' THEN 1 ELSE 0 END AS r19_discovery_title_prefers_tooltip,
    CASE WHEN NOT sc.is_form_control_selector OR sc.step_type::text IN ('form','highlight') THEN 1 ELSE 0 END AS r20_form_control_prefers_form_or_highlight
  FROM step_checks sc
)
SELECT
  ss.*,
  (
    ss.r01_has_step_type + ss.r02_step_type_allowed + ss.r03_has_selector + ss.r04_has_position + ss.r05_has_action +
    ss.r06_form_not_button_link + ss.r07_form_has_form_signal + ss.r08_checklist_has_checklist_signal + ss.r09_checklist_not_button_link + ss.r10_tooltip_action_ok +
    ss.r11_tooltip_discovery_signal + ss.r12_highlight_action_ok + ss.r13_highlight_actionable_signal + ss.r14_modal_has_modal_signal + ss.r15_tutorial_has_tutorial_signal +
    ss.r16_highlight_flag_for_highlight_form + ss.r17_no_highlight_flag_for_non_highlight_types + ss.r18_continue_title_prefers_highlight_tooltip + ss.r19_discovery_title_prefers_tooltip + ss.r20_form_control_prefers_form_or_highlight
  ) AS checks_passed,
  ROUND((
    (
      ss.r01_has_step_type + ss.r02_step_type_allowed + ss.r03_has_selector + ss.r04_has_position + ss.r05_has_action +
      ss.r06_form_not_button_link + ss.r07_form_has_form_signal + ss.r08_checklist_has_checklist_signal + ss.r09_checklist_not_button_link + ss.r10_tooltip_action_ok +
      ss.r11_tooltip_discovery_signal + ss.r12_highlight_action_ok + ss.r13_highlight_actionable_signal + ss.r14_modal_has_modal_signal + ss.r15_tutorial_has_tutorial_signal +
      ss.r16_highlight_flag_for_highlight_form + ss.r17_no_highlight_flag_for_non_highlight_types + ss.r18_continue_title_prefers_highlight_tooltip + ss.r19_discovery_title_prefers_tooltip + ss.r20_form_control_prefers_form_or_highlight
    )::numeric / 20.0
  ) * 100.0, 1) AS quality_score,
  ARRAY_REMOVE(ARRAY[
    CASE WHEN ss.r01_has_step_type = 0 THEN 'r01_has_step_type' END,
    CASE WHEN ss.r02_step_type_allowed = 0 THEN 'r02_step_type_allowed' END,
    CASE WHEN ss.r03_has_selector = 0 THEN 'r03_has_selector' END,
    CASE WHEN ss.r04_has_position = 0 THEN 'r04_has_position' END,
    CASE WHEN ss.r05_has_action = 0 THEN 'r05_has_action' END,
    CASE WHEN ss.r06_form_not_button_link = 0 THEN 'r06_form_not_button_link' END,
    CASE WHEN ss.r07_form_has_form_signal = 0 THEN 'r07_form_has_form_signal' END,
    CASE WHEN ss.r08_checklist_has_checklist_signal = 0 THEN 'r08_checklist_has_checklist_signal' END,
    CASE WHEN ss.r09_checklist_not_button_link = 0 THEN 'r09_checklist_not_button_link' END,
    CASE WHEN ss.r10_tooltip_action_ok = 0 THEN 'r10_tooltip_action_ok' END,
    CASE WHEN ss.r11_tooltip_discovery_signal = 0 THEN 'r11_tooltip_discovery_signal' END,
    CASE WHEN ss.r12_highlight_action_ok = 0 THEN 'r12_highlight_action_ok' END,
    CASE WHEN ss.r13_highlight_actionable_signal = 0 THEN 'r13_highlight_actionable_signal' END,
    CASE WHEN ss.r14_modal_has_modal_signal = 0 THEN 'r14_modal_has_modal_signal' END,
    CASE WHEN ss.r15_tutorial_has_tutorial_signal = 0 THEN 'r15_tutorial_has_tutorial_signal' END,
    CASE WHEN ss.r16_highlight_flag_for_highlight_form = 0 THEN 'r16_highlight_flag_for_highlight_form' END,
    CASE WHEN ss.r17_no_highlight_flag_for_non_highlight_types = 0 THEN 'r17_no_highlight_flag_for_non_highlight_types' END,
    CASE WHEN ss.r18_continue_title_prefers_highlight_tooltip = 0 THEN 'r18_continue_title_prefers_highlight_tooltip' END,
    CASE WHEN ss.r19_discovery_title_prefers_tooltip = 0 THEN 'r19_discovery_title_prefers_tooltip' END,
    CASE WHEN ss.r20_form_control_prefers_form_or_highlight = 0 THEN 'r20_form_control_prefers_form_or_highlight' END
  ], NULL) AS failed_rules
FROM scored_steps ss;

CREATE TEMP TABLE tmp_tour_quality AS
SELECT
  sq.tour_id,
  sq.tour_name,
  MIN(sq.created_at) AS created_at,
  MIN(sq.target_url) AS target_url,
  COUNT(*) AS steps_count,
  ROUND(AVG(sq.quality_score), 1) AS avg_step_quality_score,
  MIN(sq.quality_score) AS min_step_quality_score,
  SUM(CASE WHEN sq.quality_score < 80 THEN 1 ELSE 0 END) AS low_quality_steps,
  STRING_AGG(DISTINCT sq.step_type::text, ', ' ORDER BY sq.step_type::text) AS step_types_seen
FROM tmp_step_quality sq
GROUP BY sq.tour_id, sq.tour_name;

-- Report 1: quality score by tour
SELECT
  tq.created_at,
  tq.tour_id,
  tq.tour_name,
  tq.target_url,
  tq.steps_count,
  tq.avg_step_quality_score,
  tq.min_step_quality_score,
  tq.low_quality_steps,
  tq.step_types_seen,
  CASE
    WHEN tq.avg_step_quality_score >= 90 THEN 'good'
    WHEN tq.avg_step_quality_score >= 80 THEN 'watch'
    ELSE 'review'
  END AS quality_band
FROM tmp_tour_quality tq
ORDER BY tq.created_at DESC;

-- Report 2: low-quality steps with failed rules
SELECT
  sq.created_at,
  sq.tour_id,
  sq.tour_name,
  sq.order_index,
  sq.title,
  sq.step_type,
  sq.action,
  sq.target_selector,
  sq.quality_score,
  sq.failed_rules
FROM tmp_step_quality sq
WHERE sq.quality_score < 80
ORDER BY sq.created_at DESC, sq.order_index ASC;
