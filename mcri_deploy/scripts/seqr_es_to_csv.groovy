@Grab('org.springframework:spring-core')
@Grab('info.picocli:picocli-groovy')
@Grab('io.github.http-builder-ng:http-builder-ng-core')
@picocli.groovy.PicocliScript
@picocli.CommandLine.Command(name = "reconcile_variant_counts",
        mixinStandardHelpOptions = true,  // add --help and --version options
        version = "0.0.1",
        description = """
This script queries a Seqr Elasticsearch index and downloads it as CSV.
The output CSV has the following headers:

index_name,sample_id,variant_id,chromosome,start,end,ref,alt
""")
import groovy.json.JsonSlurper
import groovy.transform.Field
import groovyx.gpars.GParsPool
import groovyx.net.http.HttpBuilder
import org.springframework.util.StopWatch
import picocli.CommandLine

import static groovyx.net.http.ContentTypes.JSON
import static groovyx.net.http.HttpBuilder.configure

@CommandLine.Option(names = ['-o', '--outdir'], arity = '1', required = false, defaultValue = '.', description = 'Output directory of CSV files, defaults to current directory, output CSV files are named <index_name>_<sample_id>_es_variants.csv')
@Field String outputDir

@CommandLine.Option(names = ['-s', '--samples'], arity = '0..*', required = false, description = "List of samples to filter download, defaults to all.  When specifying this option, make sure it's not the last option.")
@Field List<String> includeSamples = Collections.emptyList()

@CommandLine.Option(names = ['-p', '--pageSize'], arity = '1', required = false, defaultValue = '10000', description = 'Page size when downloading from ES, defaults to 10000.')
@Field Integer pageSize

@CommandLine.Option(names = ['-t', '--threadCount'], arity = '1', required = false, defaultValue = '10', description = 'The number of samples to download simultaneously using different threads, defaults to 10.')
@Field Integer threadCount

@CommandLine.Parameters(index = '0', arity = '1', paramLabel = 'esUrl', description = 'Seqr Elasticsearch URL')
@Field String esUrl

@CommandLine.Parameters(index = '1', arity = '1', paramLabel = 'indexName', description = 'Seqr Elasticsearch index name')
@Field String indexName

@CommandLine.Spec @Field CommandLine.Model.CommandSpec spec
println "${spec.options().collect { "${it.longestName()}=${it.value}" }.join('\n')}"
println "esUrl=$esUrl, indexName=$indexName"

HttpBuilder http = configure {
    request.uri = esUrl
    request.contentType = JSON[0]
}

List<String> esSamples = getSamples(http, indexName)
println "Found samples from Elasticsearch index ${indexName}: ${esSamples.join(', ')}"

def samplesFilter = { sample ->
    (!includeSamples || includeSamples.empty) ? true : sample in includeSamples
}
List<String> samples = esSamples
        .findAll(samplesFilter)
println "Downloading for samples ${samples.join(', ')}"

String header = "indexName,sample_id,variant_id,chromosome,start,end,ref,alt,originalAltAlleles"

GParsPool.withPool(threadCount) {
    samples.eachParallel { String sampleId ->
        StopWatch sw = new StopWatch(sampleId)

        String outputFileName = "${indexName}_${sampleId}_es_variants.csv"
        String outputPath = "${outputDir ?: '.'}${File.separator}$outputFileName"
        new File(outputPath).withPrintWriter { PrintWriter pw ->
            pw.println(header)
            String firstDocBySampleEsQuery = getBySampleQuery(sampleId, 1)
            def firstDocBySampleEsQueryBody = new JsonSlurper().parseText(firstDocBySampleEsQuery)
            def respBody = http.get {
                request.uri.path = "/$indexName/_search"
                request.body = firstDocBySampleEsQueryBody
            }
            Long docCount = respBody.hits.total.value
            def pages = getPages(docCount, pageSize)
            println "Found $docCount documents for sample $sampleId, splitting into pages=$pages"

            List<String> searchAfter = ['1-']
            pages.each { page ->
                sw.start("${sampleId}-${page.page} downloading")

                println "Downloading for sample=${sampleId}, page=${page.page}, from=${page.from}, to=${page.to}, size=${page.size}"

                String bySampleEsQuery = getBySampleQuery(sampleId, page.size - 1)
                def bySampleEsQueryBody = new JsonSlurper().parseText(bySampleEsQuery)
                bySampleEsQueryBody['search_after'] = searchAfter
                bySampleEsQueryBody['sort'] = ['variantId': 'asc']

                def pageRespBody = http.get {
                    request.uri.path = "/$indexName/_search"
                    request.body = bySampleEsQueryBody
                }
                sw.stop()

                sw.start("${sampleId}-${page.page} writing CSV")
                pageRespBody.hits.hits.each { h ->
                    String type = h._type
                    String id = h._id
                    Long score = h._score
                    String ref = h._source.ref
                    String alt = h._source.alt
                    Long posStart = h._source.start
                    Long posEnd = h._source.end
                    String chrId = h._source.contig
                    String variantId = "chr$chrId-$posStart-$ref-$alt"
                    String originalAltAlleles = h._source.originalAltAlleles.join(';')

                    pw.println([indexName, sampleId, variantId, chrId, posStart, posEnd, ref, alt, originalAltAlleles].join(','))
                }
                searchAfter = pageRespBody.hits.hits[-1].sort

                sw.stop()
            }
        }

        println sw.prettyPrint()
    }
}

static List<String> getSamples(HttpBuilder http, String indexName) {
    def firstDocWithGenotypesEsQuery = """
    {
      "from": 0,
      "size": 1,
        "_source": ["_index", "_type", "_id", "_score", "contig", "docId", "variantId", "start", "end", "ref", "alt", "genotypes", "originalAltAlleles"]
    }
    """
    def firstDocWithGenotypesEsQueryBody = new JsonSlurper().parseText(firstDocWithGenotypesEsQuery)

    def respBody = http.get {
        request.uri.path = "/$indexName/_search"
        request.body = firstDocWithGenotypesEsQueryBody
    }

    def result = (respBody.hits.hits*._source.genotypes*.sample_id.flatten()).unique() as List<String>

    return result
}

static String getBySampleQuery(String sampleId, Long pageSize) {
    def result = """
    {
      "size": $pageSize,
        "_source": ["_index", "_type", "_id", "_score", "contig", "docId", "variantId", "start", "end", "ref", "alt", "originalAltAlleles"],
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

    return result
}

static def getPages(Long docCount, Integer pageSize) {
    Integer pages = Math.floor(docCount / pageSize) + 1 as Integer

    def result = (1..pages).collect { page ->
        return [
                'page': page,
                'from': (page - 1) * pageSize,
                'to'  : [docCount, (page * pageSize) - 1].min(),
                'size': pageSize
        ]
    }

    return result
}
