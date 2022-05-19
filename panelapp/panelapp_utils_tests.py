from django.test import TestCase

from panelapp.panelapp_utils import moi_to_moi_types, MoiType


class PanelappUtilsTest(TestCase):

    def test_moi_to_moi_types(self):
        self.assertListEqual(moi_to_moi_types('BIALLELIC, autosomal or pseudoautosomal'), [MoiType.BIALLELIC])
        self.assertListEqual(moi_to_moi_types('MONOALLELIC, autosomal or pseudoautosomal, NOT imprinted'),
                             [MoiType.MONOALLELIC])
        self.assertListEqual(moi_to_moi_types('Unknown'),
                             [MoiType.UNKNOWN])
        self.assertListEqual(moi_to_moi_types('BOTH monoallelic and biallelic, autosomal or pseudoautosomal'),
                             [MoiType.BIALLELIC, MoiType.MONOALLELIC])
        self.assertListEqual(moi_to_moi_types('MONOALLELIC, autosomal or pseudoautosomal, imprinted status unknown'),
                             [MoiType.MONOALLELIC])
        self.assertListEqual(
            moi_to_moi_types('X-LINKED: hemizygous mutation in males, biallelic mutations in females'),
            [MoiType.X_LINKED_RECESSIVE])
        self.assertListEqual(moi_to_moi_types('Other'),
                             [MoiType.OTHER])
        self.assertListEqual(moi_to_moi_types(
            'X-LINKED: hemizygous mutation in males, monoallelic mutations in females may cause disease (may be less severe, later onset than males)'),
            [MoiType.X_LINKED_RECESSIVE, MoiType.X_LINKED_DOMINANT])
        self.assertListEqual(moi_to_moi_types(
            'BOTH monoallelic and biallelic (but BIALLELIC mutations cause a more SEVERE disease form), autosomal or pseudoautosomal'),
            [MoiType.BIALLELIC, MoiType.MONOALLELIC])
        self.assertListEqual(moi_to_moi_types(None),
                             [MoiType.UNKNOWN])
        self.assertListEqual(moi_to_moi_types('MITOCHONDRIAL'),
                             [MoiType.MITOCHONDRIAL])
        self.assertListEqual(moi_to_moi_types(
            'MONOALLELIC, autosomal or pseudoautosomal, paternally imprinted (maternal allele expressed)'),
            [MoiType.IMPRINTED_PATERNALY_EXPRESSED])
        self.assertListEqual(moi_to_moi_types(
            'MONOALLELIC, autosomal or pseudoautosomal, maternally imprinted (paternal allele expressed)'),
            [MoiType.IMPRINTED_MATERNALY_EXPRESSED])
