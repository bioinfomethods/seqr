/**
 * @GrabConfig (systemClassLoader =true)
 */

import groovy.json.JsonSlurper
import groovy.transform.Field
import groovyx.net.http.FromServer
import org.slf4j.LoggerFactory
import picocli.CommandLine

import static ch.qos.logback.classic.Level.INFO
import static groovyx.net.http.ContentTypes.JSON
import static groovyx.net.http.HttpBuilder.configure
import static org.slf4j.Logger.ROOT_LOGGER_NAME

@Grab('ch.qos.logback:logback-classic')
@Grab('info.picocli:picocli-groovy')
@Grab('io.github.http-builder-ng:http-builder-ng-core')
@picocli.groovy.PicocliScript
@picocli.CommandLine.Command(name = "compare_es_index",
        mixinStandardHelpOptions = true,  // add --help and --version options
        version = "0.0.1",
        description = """
This script compares two instances of Seqr Elasticsearch and ensures the source and target index match in the following criteria:
* Variant counts match
* First and last 1000 documents (sorted by variantId) match
* If list of sample IDs are provided, for each sample ID, variant counts by each sample are also compared.

then run script as follows:
groovy compare_es_index.groovy source_index_name http://localhost:9200 username password target_index_name http://localhost:9200 username password sampleIds...
""")

@CommandLine.Parameters(index = '0', arity = '1', paramLabel = 'sourceIndex', description = 'Source index name')
@Field String sourceIndex
@CommandLine.Parameters(index = '1', arity = '1', paramLabel = 'sourceEsUrl', defaultValue = 'http://localhost:19200', description = 'Source Elasticsearch URL')
@Field String sourceEsUrl
@CommandLine.Parameters(index = '2', arity = '1', paramLabel = 'sourceEsUsername', defaultValue = 'elastic', description = 'Source Elasticsearch username')
@Field String sourceEsUsername
@CommandLine.Parameters(index = '3', arity = '1', paramLabel = 'sourceEsPassword', defaultValue = 'password', description = 'Source Elasticsearch password')
@Field String sourceEsPassword
@CommandLine.Parameters(index = '4', arity = '1', paramLabel = 'targetIndex', description = 'Target index name')
@Field String targetIndex
@CommandLine.Parameters(index = '5', arity = '1', paramLabel = 'targetEsUrl', defaultValue = 'http://localhost:29200', description = 'Target Elasticsearch URL')
@Field String targetEsUrl
@CommandLine.Parameters(index = '6', arity = '1', paramLabel = 'targetEsUsername', defaultValue = 'elastic', description = 'Target Elasticsearch username')
@Field String targetEsUsername
@CommandLine.Parameters(index = '7', arity = '1', paramLabel = 'targetEsPassword', defaultValue = 'password', description = 'Target Elasticsearch password')
@Field String targetEsPassword

@CommandLine.Option(arity = '1', names = ['-n', '--docCount'], defaultValue = '1000', description = 'number of documents to compare')
@Field Integer docCount

@CommandLine.Parameters(index = '8..*', paramLabel = "SAMPLES", description = "one or more sample IDs")
@Field List<String> sampleIds = Collections.emptyList()

def printerr = System.err.&println

def projectIndices = [("${sourceIndex}".toString()): "${targetIndex}"]

def ROOT_LOG = LoggerFactory.getLogger(ROOT_LOGGER_NAME)
ROOT_LOG.level = INFO

['asc', 'desc'].each { String indexSortOrder ->
    def ES_QUERY = """
    {
        "_source": {
            "exclude": ["_index", "_type"]
        },
        "query": {
            "match_all": {}
        },
        "track_total_hits": true,
        "from": 0,
        "size": $docCount,
        "sort": {
          "variantId": "$indexSortOrder"
        }
    }
    """

    projectIndices.each { source, target ->
        println "Comparing $docCount documents in $indexSortOrder order, sourceIndex=$source to targetIndex=$target"

        def body = new JsonSlurper().parseText(ES_QUERY)

        def sourceResult = configure {
            request.auth.basic sourceEsUsername, sourceEsPassword
            request.uri = sourceEsUrl
            request.contentType = JSON[0]
        }.get {
            request.uri.path = "/$source/_search"
            request.body = body
            response.failure { FromServer fs, def respBody ->
                printerr "Not found in sourceIndex, skipping... sourceIndex=$source, statusCode=${fs.statusCode}, message=${fs.message}"
            }
        }

        if (sourceResult) {
            Long sourceDocCount = sourceResult.hits.total.value
            def sourceDocSources = sourceResult.hits.hits._source

            def targetResult = configure {
                request.auth.basic targetEsUsername, targetEsPassword
                request.uri = targetEsUrl
                request.contentType = JSON[0]
            }.get {
                request.uri.path = "/$target/_search"
                request.body = body
                response.failure { FromServer fs, def respBody ->
                    printerr "ERROR: Elasticsearch targetIndex=$target found in source but not in target."
                }
            }

            if (targetResult) {
                Long targetDocCount = targetResult.hits.total.value
                def targetDocSources = targetResult.hits.hits._source

                assert sourceDocCount == targetDocCount

                sourceDocSources.eachWithIndex { sourceDoc, docIdx ->
                    String docId = sourceDoc.docId
                    def targetDocs = targetDocSources.findAll { it.docId == docId }
                    if (targetDocs.size() == 1) {
                        def targetDoc = targetDocs[0]
//                        println "Comparing variant=${docId}"
                        sourceDoc.keySet().each { k ->
                            def sourceDocProp = sourceDoc[k]
                            def targetDocProp = targetDoc[k]

                            // Need to confirm logic on how main transcript is decided, skip for now
                            if (!(k in ['mainTranscript_hgvs', 'mainTranscript_hgvsc', 'mainTranscript_hgvsp', 'mainTranscript_protein_id', 'mainTranscript_gene_id', 'mainTranscript_gene_symbol', 'mainTranscript_cdna_start', 'mainTranscript_cdna_end', 'mainTranscript_transcript_id', 'sortedTranscriptConsequences', 'mainTranscript_polyphen_prediction', 'mainTranscript_biotype'])) {
                                if (sourceDocProp instanceof Collection) {
                                    assert sourceDocProp?.sort(false) == targetDocProp?.sort(false), "$docId, $k not equal"
                                } else {
                                    assert sourceDocProp == targetDocProp, "$docId, $k not equal"
                                }
                            } else if (k == 'sortedTranscriptConsequences') {
                                // fuzzy equals check on sortedTranscriptConsequences
                                assert sourceDocProp.every { s ->
                                    targetDocProp.any { t ->
                                        s.transcript_id == t.transcript_id
                                                && s.major_consequence == t.major_consequence
                                                && s.hgvsc == t.hgvsc
                                                && s.protein_id == t.protein_id
                                                && s.major_consequence_rank == t.major_consequence_rank
                                    }
                                }, "$docId, $k not equal"
                                assert (sourceDocProp?.size() ?: 0) == (targetDocProp?.size() ?: 0), "$docId, $k not equal"
                            }
                        }
                    } else {
                        printerr "Found more than one target docs for variant=${docId}"
                    }
                }
            }
        }
    }
}

projectIndices.each { source, target ->
    sampleIds.each { String sampleId ->
        def bySampleEsQuery = """
  {
    "query": {
      "bool": {
        "filter": [
          {
            "bool": {
              "must": [
                {
                  "bool": {
                    "should": [
                      {
                        "terms": {
                          "samples_num_alt_1": [
                            "$sampleId"
                          ]
                        }
                      },
                      {
                        "terms": {
                          "samples_num_alt_2": [
                            "$sampleId"
                          ]
                        }
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    },
    "track_total_hits": true
  }
  """

        def body = new JsonSlurper().parseText(bySampleEsQuery)

        def sourceResult = configure {
            request.auth.basic sourceEsUsername, sourceEsPassword
            request.uri = sourceEsUrl
            request.contentType = JSON[0]
        }.get {
            request.uri.path = "/$source/_search"
            request.body = body
            response.failure { FromServer fs, def respBody ->
                printerr "Not found in sourceIndex, skipping... sourceIndex=$source, statusCode=${fs.statusCode}, message=${fs.message}"
            }
        }

        if (sourceResult) {
            Long sourceDocCount = sourceResult.hits.total.value

            def targetResult = configure {
                request.auth.basic targetEsUsername, targetEsPassword
                request.uri = targetEsUrl
                request.contentType = JSON[0]
            }.get {
                request.uri.path = "/$target/_search"
                request.body = body
                response.failure { FromServer fs, def respBody ->
                    printerr "ERROR: Elasticsearch targetIndex=$target found in source but not in target."
                }
            }

            if (targetResult) {
                Long targetDocCount = targetResult.hits.total.value
                assert sourceDocCount == targetDocCount
                println "Variant counts match: sourceIndex=$source, targetIndex=$target, sampleId=$sampleId, sourceCount=$sourceDocCount, targetCount=$targetDocCount"
            }
        }
    }
}
