/**
 * @GrabConfig (systemClassLoader =true)
 */

import groovy.json.JsonSlurper
import groovy.sql.Sql
import groovy.transform.Field
import groovyx.net.http.FromServer
import picocli.CommandLine

@GrabConfig(systemClassLoader = true)
// systemClassLoader is needed to ensure DriverManager can find the DB driver
@Grab('info.picocli:picocli-groovy')
@Grab('org.postgresql:postgresql')
@Grab('io.github.http-builder-ng:http-builder-ng-core')
@picocli.groovy.PicocliScript
@picocli.CommandLine.Command(name = "reconcile_es_indices",
        mixinStandardHelpOptions = true,  // add --help and --version options
        version = "0.0.1",
        description = """
This script compares two instances of Seqr Elasticsearch and ensures all their indices have the same document counts.
It also compares the first 1000 documents and ensure all contents (hits) are identical.
Requires access to Seqr DB, Seqr source ES and the other Seqr ES service to compare with.

To run this script locally, create SSH tunnel as follows:
seqrDb: ssh -L 0.0.0.0:15432:localhost:5432 seqr@seqr-test-gcp
sourceEsUrl: ssh -L 0.0.0.0:19200:\$(gcloud compute addresses list --filter='name=seqr-prod-b-es' --format='value(address)'):30100 seqr@seqrprodb
targetEsUrl: ssh -L 0.0.0.0:29200:\$(gcloud compute addresses list --filter='name=seqr-prod-a-es' --format='value(address)'):30100 seqr@seqrproda

then run script as follows:
groovy reconcile_es_indices.groovy "jdbc:postgresql://localhost:15432/seqrdb?user=postgres&password=\$DB_PASSWORD" http://localhost:9200 elastic \$PASSWORD http://localhost:19200 elastic \$PASSWORD
""")
import java.sql.Connection
import java.sql.DriverManager

import static groovyx.net.http.ContentTypes.JSON
import static groovyx.net.http.HttpBuilder.configure

@CommandLine.Parameters(index = '0', arity = '1', paramLabel = 'seqrDbConnStr', defaultValue = 'jdbc:postgresql://localhost:15432/seqrdb?user=postgres', description = 'Seqr DB JDBC URL')
@Field String seqrDbConnStr
@CommandLine.Parameters(index = '1', arity = '1', paramLabel = 'sourceEsUrl', defaultValue = 'http://localhost:19200', description = 'Source Elasticsearch URL')
@Field String sourceEsUrl
@CommandLine.Parameters(index = '2', arity = '1', paramLabel = 'sourceEsUsername', defaultValue = 'elastic', description = 'Source Elasticsearch username')
@Field String sourceEsUsername
@CommandLine.Parameters(index = '3', arity = '1', paramLabel = 'sourceEsPassword', defaultValue = 'password', description = 'Source Elasticsearch password')
@Field String sourceEsPassword
@CommandLine.Parameters(index = '4', arity = '1', paramLabel = 'targetEsUrl', defaultValue = 'http://localhost:29200', description = 'Target Elasticsearch URL')
@Field String targetEsUrl
@CommandLine.Parameters(index = '5', arity = '1', paramLabel = 'targetEsUsername', defaultValue = 'elastic', description = 'Target Elasticsearch username')
@Field String targetEsUsername
@CommandLine.Parameters(index = '6', arity = '1', paramLabel = 'targetEsPassword', defaultValue = 'password', description = 'Target Elasticsearch password')
@Field String targetEsPassword

@CommandLine.Option(arity = '1', names = ['-n', '--docCount'], defaultValue = '1000', description = 'number of documents to compare')
@Field Integer docCount

Properties props = new Properties()
props.setProperty('readOnly', 'true')
Class.forName("org.postgresql.Driver")
Connection seqrDbConn = DriverManager.getConnection(seqrDbConnStr, props)
Sql seqrDb = new Sql(seqrDbConn)

def projectIndices = seqrDb.rows("""
WITH r AS (
  SELECT sp.guid project_guid, sf.family_id, sf.display_name,
    si.individual_id, si.sex, si.affected,
    ss.guid sample_guid, ss.created_date, ss.last_modified_date, ss.sample_id, ss.sample_type,
    ss.dataset_type, ss.elasticsearch_index, ss.is_active
  FROM seqr_project sp
       JOIN seqr_family sf ON sp.id = sf.project_id
       JOIN seqr_individual si ON sf.id = si.family_id
       JOIN seqr_sample ss ON si.id = ss.individual_id
  WHERE ss.is_active IS TRUE
    AND sp.guid NOT IN ('R0002_test_tag_creation')
    -- AND ss.elasticsearch_index = 'tran2_vumc_wgs_grch38_20200612'
)
SELECT project_guid, elasticsearch_index, COUNT(sample_id) sample_count
FROM r
GROUP BY project_guid, elasticsearch_index
""")

def ES_QUERY = """
{
    "query": {
        "match_all": {}
    },
    "track_total_hits": true,
    "from": 0,
    "size": $docCount
}
"""

//def INDICES_TO_SKIP_DOCS_ASSERT = ['tran2_vumc_wgs_grch38_20200612']
def INDICES_TO_SKIP_DOCS_ASSERT = []

projectIndices.each { row ->
    String projectId = row.project_guid
    String index = row.elasticsearch_index
    Integer sampleCount = row.sample_count as Integer
    println "Comparing projectId=$projectId, index=$index, sampleCount=$sampleCount"

    def body = new JsonSlurper().parseText(ES_QUERY)

    def sourceResult = configure {
        request.auth.basic sourceEsUsername, sourceEsPassword
        request.uri = sourceEsUrl
        request.contentType = JSON[0]
    }.get {
        request.uri.path = "/$index/_search"
        request.body = body
        response.failure { FromServer fs, def respBody ->
            println "Not found in source index, skipping... projectId=$projectId, index=$index, sampleCount=$sampleCount, statusCode=${fs.statusCode}, message=${fs.message}"
        }
    }

    if (sourceResult) {
        Long sourceDocCount = sourceResult.hits.total.value
        def sourceDocs = sourceResult.hits.hits

        def targetResult = configure {
            request.auth.basic targetEsUsername, targetEsPassword
            request.uri = targetEsUrl
            request.contentType = JSON[0]
        }.get {
            request.uri.path = "/$index/_search"
            request.body = body
            response.failure { FromServer fs, def respBody ->
                println "ERROR: Elasticsearch index=$index found in source but not in target."
            }
        }

        if (targetResult) {
            Long targetDocCount = targetResult.hits.total.value
            def targetDocs = targetResult.hits.hits

            assert sourceDocCount == targetDocCount
            if (!(index in INDICES_TO_SKIP_DOCS_ASSERT)) {
                assert sourceDocs == targetDocs
            } else {
                println "Skipping docs compare"
            }
        }
    }
}
