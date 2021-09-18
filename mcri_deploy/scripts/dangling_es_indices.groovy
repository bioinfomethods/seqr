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
@picocli.CommandLine.Command(name = "dangling_es_indices",
        mixinStandardHelpOptions = true,  // add --help and --version options
        version = "0.0.1",
        description = """
This script reconciles Elasticsearch indices with Seqr application.
""")
import java.sql.Connection
import java.sql.DriverManager

import static groovyx.net.http.ContentTypes.JSON
import static groovyx.net.http.HttpBuilder.configure

@CommandLine.Parameters(index = '0', arity = '1', paramLabel = 'seqrDbConnStr', defaultValue = 'jdbc:postgresql://localhost:15432/seqrdb?user=postgres', description = 'Seqr DB JDBC URL')
@Field String seqrDbConnStr
@CommandLine.Parameters(index = '1', arity = '1', paramLabel = 'esUrl', defaultValue = 'http://localhost:9200', description = 'Elasticsearch URL')
@Field String esUrl

@CommandLine.Spec @Field CommandLine.Model.CommandSpec spec
println "${spec.options().collect { "${it.longestName()}=${it.value}" }.join('\n')}"

def STYLES = [
        HEADER   : '\033[95m',
        WARNING  : '\033[93m',
        FAIL     : '\033[91m',
        ENDC     : '\033[0m',
        BOLD     : '\033[1m',
        UNDERLINE: '\033[4m',
]

Class.forName("org.postgresql.Driver")
Connection seqrDbConn = DriverManager.getConnection(seqrDbConnStr, ['readOnly': 'true'] as Properties)
Sql seqrDb = new Sql(seqrDbConn)

List<String> seqrIndexDetails = seqrDb.rows("""
WITH sample_indices AS (
  SELECT ss.id, REGEXP_SPLIT_TO_TABLE(ss.elasticsearch_index, ',') elasticsearch_index
  FROM seqr_sample ss
),
r AS (
  SELECT ss.guid sample_guid, ss.created_date sample_created_date, ss.last_modified_date sample_last_modified_date, ss.sample_id, ss.sample_type, ses.elasticsearch_index, ss.loaded_date index_loaded_date, ss.is_active index_is_active,
    si.sex, si.affected, si.display_name ind_display_name,
    sf.guid family_guid, sf.family_id, sf.display_name family_display_name,
    sp.guid project_guid, sp.name project_name, sp.description project_description, sp.genome_version
  FROM seqr_sample ss
    JOIN sample_indices ses ON ses.id = ss.id
    LEFT JOIN seqr_individual si ON ss.individual_id = si.id
    LEFT JOIN seqr_family sf ON si.family_id = sf.id
    LEFT JOIN seqr_project sp ON sf.project_id = sp.id
)
SELECT *
FROM r
""")
List<String> seqrIndices = seqrIndexDetails.collect { it.elasticsearch_index }

String esResult = configure {
    request.uri = esUrl
    request.contentType = JSON[0]
}.get {
    request.uri.path = "/_cat/indices"
    response.failure { FromServer fs, def respBody ->
        println "Error querying ${request.uri.path}"
    }
}

List<String> esIndices = []
esResult.splitEachLine(/\s+/) { def lineItems ->
    esIndices << lineItems[2]
}
List<String> applicEsIndices = esIndices.findAll { !it.startsWith('.') && !(it in ['index_operations_log']) }

List<String> inEsNotInSeqr = applicEsIndices - seqrIndices
println "${STYLES.HEADER}Indices in Elasticsearch but not associated in Seqr:\n${STYLES.ENDC}${inEsNotInSeqr.join('\n')}\n"
inEsNotInSeqr.each { String indexToDelete ->
    println "curl -X DELETE $esUrl/$indexToDelete"
}

List<String> inSeqrNotInEs = seqrIndices - applicEsIndices
println "${STYLES.HEADER}Indices associated in Seqr but not in Elasticsearch:\n${STYLES.ENDC}${inSeqrNotInEs.join('\n')}\n"
inSeqrNotInEs.each { String notInEs ->
    seqrIndexDetails.findAll { it.elasticsearch_index == notInEs }.each { println it }
}
