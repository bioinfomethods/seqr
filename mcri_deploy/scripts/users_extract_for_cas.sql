WITH project_user AS (
  SELECT DISTINCT sp.guid project_guid, sp.name project_name, au.username, 'password' "password", au.email
  FROM seqr_project sp
    JOIN auth_group ag on ag.id = sp.can_view_group_id
    JOIN auth_user_groups aug on ag.id = aug.group_id
    JOIN auth_user au on (aug.user_id = au.id OR au.is_superuser = True)
  WHERE sp.guid IN ('R0034_rdnow_genomes', 'R0024_tran2_vumc_restricted', 'R0025_tran2_iee_surgical')
)
SELECT *
FROM project_user pu
--WHERE pu.email IN ('tommy.li@mcri.edu.au', 'cas.simons@mcri.edu.au')
ORDER BY pu.project_guid, pu.email
;
