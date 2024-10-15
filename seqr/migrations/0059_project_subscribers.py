# Generated by Django 3.2.23 on 2024-02-07 20:52

from django.db import migrations, models
import django.db.models.deletion
from django.utils.text import slugify
import uuid


def add_subscriber_group(apps, schema_editor):
    Project = apps.get_model('seqr', 'Project')
    Group = apps.get_model('auth', 'Group')
    User = apps.get_model('auth', 'User')
    db_alias = schema_editor.connection.alias
    projects = Project.objects.using(db_alias).all()
    for project in projects:
        project.subscribers = Group.objects.create(name=f'{slugify(project.name.strip())[:30]}_subscribers_{uuid.uuid4()}')
        users = set()
        if project.created_by:
            users.add(project.created_by)
        if not users and project.can_edit_group:
            users.update(project.can_edit_group.user_set.all())
        if not users and project.can_view_group:
            users.update(project.can_view_group.user_set.all())
        if not users:
            users.update(User.objects.filter(email='hsnow@broadinstititue.org').all())
        project.subscribers.user_set.add(*users)
    Project.objects.using(db_alias).bulk_update(projects, ['subscribers'])


class Migration(migrations.Migration):

    dependencies = [
        ('auth', '0012_alter_user_first_name_max_length'),
        ('seqr', '0058_alter_sample_dataset_type'),
    ]

    operations = [
        migrations.AddField(
            model_name='project',
            name='subscribers',
            field=models.ForeignKey(default=1, on_delete=django.db.models.deletion.CASCADE, related_name='+', to='auth.group'),
            preserve_default=False,
        ),
        migrations.RunPython(add_subscriber_group, reverse_code=migrations.RunPython.noop),
    ]
