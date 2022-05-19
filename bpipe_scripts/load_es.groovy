options {
    project 'Project that VCF will be loaded into', args:1, required: true
    vcf 'VCF location in google cloud, bgz extension', args:1, required: false
    mt 'Hail matrix table containing the variants', args:1, required: true
    index 'Elastic Search index to load the variants into', args:1, required: false
    genome_version 'Genome version 37 or 38 (default: inferred by copying VCF from gcloud)', args:1, required: false
    sample_type 'WES or WGS (default: WES)', args: 1, required: false
}

// ELASTIC_SEARCH_HOST = gngs.Utils.exec("""
// /snap/bin/kubectl get nodes --output=jsonpath={.items[0].status.addresses[?(@.type=="ExternalIP")].address}
// """, throwOnError:true).out.toString().trim()

ELASTIC_SEARCH_HOST = '34.87.227.151'
println "Elastic Search Host: $ELASTIC_SEARCH_HOST"

// r0004_sw_001__wes__grch38__variants__20191211

SAMPLE_TYPE = opts.sample_type?:'WES'

VCF_GS_PATH=opts.vcf?:opts.mt.replaceAll('\\.mt$','.vcf')

load_mt_to_seqr = {

    produce(file(opts.mt).name + '.import.log') {
            exec """

                source /home/seqr/anaconda3/bin/activate /home/seqr/anaconda3/envs/hail

                export PYTHONPATH=/home/seqr/seqr/hail_elasticsearch_pipelines:/home/seqr/seqr/hail_elasticsearch_pipelines/luigi_pipeline

                python3 -m seqr_loading SeqrMTToESTask --local-scheduler
                     --source-paths  $VCF_GS_PATH
                     --dest-path $opts.mt
                     --genome-version $GENOME_VERSION
                     --sample-type $SAMPLE_TYPE
                     --es-host $ELASTIC_SEARCH_HOST
                     --es-port 30100
                     --es-index $ES_INDEX 2>&1 | tee $output
            """
    }
}

init = {
    branch.dir = opts.project

    branch.vcf_name = new File(VCF_GS_PATH).name

    if(opts.genome_version) {
            branch.GENOME_VERSION = opts.genome_version
    }
    else {
            if(!opts.vcf)
                fail 'If -vcf is not provided, -genome_version must be provided'

            produce(vcf_name) {
              exec """
                  gsutil cp $VCF_GS_PATH $output.bgz
              """
            }

            branch.GENOME_BUILD = new gngs.VCF(output.bgz).sniffGenomeBuild()

            branch.GENOME_VERSION = (GENOME_BUILD == 'hg19' || GENOME_BUILD == 'GRCh37') ? 37 : 38
            println "Detected genome build $GENOME_BUILD"
    }

    branch.ES_INDEX = opts.index ?: "${opts.project}_${SAMPLE_TYPE.toLowerCase()}_grch${GENOME_VERSION}_${(new Date()).format('YMMdd')}"

    println "Detected genome version $GENOME_VERSION"
    println "ES Index name will be: $ES_INDEX"
}

done = {
    println "*" * 100
    println "Finished!  Please import elastic search index: $ES_INDEX to your SeqR project"
    println "*" * 100
}

run {
    init + load_mt_to_seqr + done
}
