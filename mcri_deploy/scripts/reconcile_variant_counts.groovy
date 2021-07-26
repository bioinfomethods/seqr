@Grab('info.picocli:picocli-groovy')
@Grab('org.postgresql:postgresql')
@Grab('io.github.http-builder-ng:http-builder-ng-core')
@picocli.groovy.PicocliScript
@picocli.CommandLine.Command(name = "reconcile_variant_counts",
  mixinStandardHelpOptions = true,  // add --help and --version options
  version = "0.0.1",
  description = """
This script queries Seqr Elasticsearch index and compares document count with the counts
provided in TSV.  The TSV is expected in the following format:

170728_K00164_0131_ML171267_17W000577_Exome-000066_SSQXTCRE 26669
170908_K00164_0132_ML171472_17W000630_STAR-20170905_SSQXTCRE 25850
170908_K00164_0132_ML171475_17W000652_STAR-20170905_SSQXTCRE 26252
""")
import groovy.json.JsonSlurper
import groovy.transform.Field
import picocli.CommandLine

import static groovyx.net.http.ContentTypes.JSON
import static groovyx.net.http.HttpBuilder.configure

@CommandLine.Parameters(index = '0', arity = '1', paramLabel = 'esUrl', defaultValue = 'http://localhost:19200', description = 'Seqr Elasticsearch URL')
@Field String esUrl
@CommandLine.Parameters(index = '1', arity = '1', paramLabel = 'index', description = 'Seqr Elasticsearch index name')
@Field String index
@CommandLine.Parameters(index = '2', arity = '1', paramLabel = 'variantCountPath', description = 'TSV file path with expected variant counts per sample')
@Field String variantCountPath

def errors = []

new File(variantCountPath).splitEachLine(/\t/) { def lineItems ->
  String sampleId = lineItems[0].trim()
  Integer vcfVariantCount = lineItems[1].trim() as Integer

  // println "Reconciling sampleId=$sampleId, expVariantCount=vcfVariantCount"

  def esQuery = """
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
  def body = new JsonSlurper().parseText(esQuery)

  def result = configure {
    request.uri = esUrl
    request.contentType = JSON[0]
  }.get {
    request.uri.path = "/$index/_search"
    request.body = body
  }

  Integer indexVariantCount = result.hits.total.value

  if (indexVariantCount < vcfVariantCount || indexVariantCount > vcfVariantCount * 1.1) {
    errors << "Elasticsearch index variant counts not within range of expected VCF variant counts, index=$index, sampleId=$sampleId, vcfVariantCount=$vcfVariantCount, indexVariantCount=$indexVariantCount, diff=${indexVariantCount - vcfVariantCount}"
  }
}

if (errors.empty) {
  println "All samples in index $index reconcile within range of expected variant counts."
  System.exit(0)
}
else {
  println errors.join('\n')
  System.exit(1)
}
