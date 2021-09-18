WITH project_user AS (
  SELECT DISTINCT sp.guid project_guid, sp.name project_name, au.username, au.password, au.email
  FROM seqr_project sp
    JOIN auth_group ag on ag.id = sp.can_view_group_id
    JOIN auth_user_groups aug on ag.id = aug.group_id
    JOIN auth_user au on aug.user_id = au.id
  WHERE sp.guid IN ('R0034_rdnow_genomes', 'R0024_tran2_vumc_restricted', 'R0025_tran2_iee_surgical')
)
SELECT *
FROM project_user pu
ORDER BY pu.project_guid, pu.email
;
