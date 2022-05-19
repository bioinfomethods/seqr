#%%
import hail as hl

mt = hl.read_matrix_table('/Users/tommyli/Development/mcri/seqr-mcri/imports/projects/test_genetale/EXAMPLE_SAMPLE.final.genetale.ann.mt')
mt.count()
# mt.describe()
mt.aIndex.show()
mt.genetaleGeneClass.show(50)


#%%
import hail as hl

# mt = hl.import_vcf('genetale/example.of.genetale.ann.vcf', reference_genome='GRCh38')
# mt = hl.import_vcf('/Users/tommyli/mcri_home/genetale/genetale/EXAMPLE_SAMPLE.final.genetale.ann.mt', reference_genome='GRCh38')
# mt = hl.read_matrix_table('/misc/bioinf-ops/seqr/imports/projects/test_genetale/EXAMPLE_SAMPLE.final.genetale.ann.mt')
mt = hl.read_matrix_table('/Users/tommyli/Development/mcri/seqr-mcri/imports/projects/test_genetale_v2/EXAMPLE_SAMPLE.final.genetale.ann.mt')
mt.count()
# mt.describe()
# mt.genetale_AllDiseases.show(50)
# mt.genetale_AllInheritances.show(50)
# mt.genetale_AllResFlag.show(50)
# mt.genetale_Flag.show(50)
# mt.genetale_GeneClassInfo.show(50)
# mt.genetale_GeneClass.show(50)
# mt.genetale_Previous.show(50)
# mt.genetale_VarClassNum.show(50)
mt.domains.show()

#%%
def infoToStruct(v):
  splitted = v.split(':')
  print(f"splitted[0]={str(splitted[0])},splitted[1]={str(splitted[1])}")
  return {splitted[0]:splitted[1]}
  return hl.struct(**{str(splitted[0]):str(splitted[1])})


#%%
gtmt = hl.import_vcf('/Users/tommyli/mcri_home/genomicsData/test_38.8k.vcf', reference_genome='GRCh38')

gtmt.describe()
# gtmt.info.show()
# mt.info.show()
hl.is_defined(gtmt.info.get('GT.GeneClass'))
