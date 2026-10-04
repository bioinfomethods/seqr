"""MCRI-local extensions to the seqr data model.

Kept in `mcri_ext` rather than as new fields on `seqr.Project` / `seqr.Individual` so
that MCRI state does not conflict with upstream seqr migrations.
"""
from django.contrib.auth.models import User
from django.db import models


class VariantCountExclusionMixin(models.Model):
    """Shared audit fields for the variant-count exclusion tables.

    Exclusion is deliberately modelled as *presence of a row*, not as a boolean flag.
    A project or individual with no row here is counted. That makes "counted" the
    default state with nothing to set, and makes excluding something an explicit,
    attributable action.
    """

    reason = models.TextField(
        help_text='Why this is excluded from variant observation counts.',
    )
    created_date = models.DateTimeField(auto_now_add=True, db_index=True)
    created_by = models.ForeignKey(User, null=True, blank=True, on_delete=models.SET_NULL)

    class Meta:
        abstract = True

    def __str__(self):
        return f'{self.__class__.__name__}({self.target_id}): {self.reason}'


class ExcludedCountProject(VariantCountExclusionMixin):
    """A project whose samples do not contribute to variant observation counts."""

    project = models.OneToOneField(
        'seqr.Project', on_delete=models.CASCADE, related_name='count_exclusion',
    )

    class Meta:
        db_table = 'mcri_excluded_count_project'

    @property
    def target_id(self):
        return self.project.guid


class ExcludedCountIndividual(VariantCountExclusionMixin):
    """An individual whose samples do not contribute to variant observation counts."""

    individual = models.OneToOneField(
        'seqr.Individual', on_delete=models.CASCADE, related_name='count_exclusion',
    )

    class Meta:
        db_table = 'mcri_excluded_count_individual'

    @property
    def target_id(self):
        return self.individual.guid


class ProjectAssay(models.Model):
    """Marks a project as holding a non-default assay type.

    Variant observation counts are broken down per assay. WES and WGS come straight from
    `Sample.sample_type`, which ClickHouse already carries on `project_gt_stats`. Long-read
    data has no `sample_type` of its own upstream, and adding one would mean changing the
    Django model, the loading pipeline and several places in the search layer that assume
    exactly two sample types.

    MCRI loads long-read data into dedicated projects, so the assay can instead be derived
    from project membership. A project with no row here is short-read and is counted by its
    samples' `sample_type` exactly as before -- so this is additive, and the default needs
    no configuration.
    """

    ASSAY_LRS = 'LRS'
    ASSAY_CHOICES = ((ASSAY_LRS, 'Long read'),)

    project = models.OneToOneField(
        'seqr.Project', on_delete=models.CASCADE, related_name='count_assay',
    )
    assay = models.CharField(max_length=10, choices=ASSAY_CHOICES)

    class Meta:
        db_table = 'mcri_project_assay'

    def __str__(self):
        return f'{self.project.guid}: {self.assay}'
