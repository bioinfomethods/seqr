/**
 * This script finds latest disk snapshots and generates gcloud commands
 * for creating new Google PersistentDisk.  This script requires gcloud
 * installed and initialised.
 */

String REGION = 'australia-southeast1'
String ZONE = 'australia-southeast1-b'
String RESOURCE_POLICIES = 'disk-snapshot-7-day-rolling'

def TEST_DISK_CONFIGS = [
        ['oldDiskName': 'pd-es-data-0', 'oldK8StatefulSetVolumeClaimName': 'pvc-es-data-es-data-0', 'newK8StatefulSetVolumeClaimName': 'elasticsearch-data-es-data-test-0', 'newPdDiskName': 'pd-es-data-test-0', 'size': '200Gi', 'type': 'pd-standard', 'labels': ['goog-gke-volume=', 'env=test']],
        ['oldDiskName': 'pd-es-data-1', 'oldK8StatefulSetVolumeClaimName': 'pvc-es-data-es-data-1', 'newK8StatefulSetVolumeClaimName': 'elasticsearch-data-es-data-test-1', 'newPdDiskName': 'pd-es-data-test-1', 'size': '200Gi', 'type': 'pd-standard', 'labels': ['goog-gke-volume=', 'env=test']],
        ['oldDiskName': 'pd-es-data-2', 'oldK8StatefulSetVolumeClaimName': 'pvc-es-data-es-data-2', 'newK8StatefulSetVolumeClaimName': 'elasticsearch-data-es-data-test-2', 'newPdDiskName': 'pd-es-data-test-2', 'size': '200Gi', 'type': 'pd-standard', 'labels': ['goog-gke-volume=', 'env=test']],
        ['oldDiskName': 'pd-es-master-0', 'oldK8StatefulSetVolumeClaimName': 'pvc-es-master-es-master-0', 'newK8StatefulSetVolumeClaimName': 'elasticsearch-data-es-master-test-0', 'newPdDiskName': 'pd-es-master-test-0', 'size': '10Gi', 'type': 'pd-standard', 'labels': ['goog-gke-volume=', 'env=test']],
        ['oldDiskName': 'pd-es-master-1', 'oldK8StatefulSetVolumeClaimName': 'pvc-es-master-es-master-1', 'newK8StatefulSetVolumeClaimName': 'elasticsearch-data-es-master-test-1', 'newPdDiskName': 'pd-es-master-test-1', 'size': '10Gi', 'type': 'pd-standard', 'labels': ['goog-gke-volume=', 'env=test']],
]

def PROD_DISK_CONFIGS = [
        ['oldDiskName': 'pd-es-data-0', 'oldK8StatefulSetVolumeClaimName': 'pvc-es-data-es-data-0', 'newK8StatefulSetVolumeClaimName': 'elasticsearch-data-es-data-prod-0', 'newPdDiskName': 'pd-es-data-prod-0', 'size': '200Gi', 'type': 'pd-standard', 'labels': ['goog-gke-volume=', 'env=prod']],
        ['oldDiskName': 'pd-es-data-1', 'oldK8StatefulSetVolumeClaimName': 'pvc-es-data-es-data-1', 'newK8StatefulSetVolumeClaimName': 'elasticsearch-data-es-data-prod-1', 'newPdDiskName': 'pd-es-data-prod-1', 'size': '200Gi', 'type': 'pd-standard', 'labels': ['goog-gke-volume=', 'env=prod']],
        ['oldDiskName': 'pd-es-data-2', 'oldK8StatefulSetVolumeClaimName': 'pvc-es-data-es-data-2', 'newK8StatefulSetVolumeClaimName': 'elasticsearch-data-es-data-prod-2', 'newPdDiskName': 'pd-es-data-prod-2', 'size': '200Gi', 'type': 'pd-standard', 'labels': ['goog-gke-volume=', 'env=prod']],
        ['oldDiskName': 'pd-es-master-0', 'oldK8StatefulSetVolumeClaimName': 'pvc-es-master-es-master-0', 'newK8StatefulSetVolumeClaimName': 'elasticsearch-data-es-master-prod-0', 'newPdDiskName': 'pd-es-master-prod-0', 'size': '10Gi', 'type': 'pd-standard', 'labels': ['goog-gke-volume=', 'env=prod']],
        ['oldDiskName': 'pd-es-master-1', 'oldK8StatefulSetVolumeClaimName': 'pvc-es-master-es-master-1', 'newK8StatefulSetVolumeClaimName': 'elasticsearch-data-es-master-prod-1', 'newPdDiskName': 'pd-es-master-prod-1', 'size': '10Gi', 'type': 'pd-standard', 'labels': ['goog-gke-volume=', 'env=prod']],
]

def out = new StringBuilder()
def err = new StringBuilder()
def printerr = System.err.&println

Process proc = "gcloud compute snapshots list --format=csv(name,sourceDisk.scope():label=SRC_DISK,status)".execute()
proc.waitForProcessOutput(out, err)

if (err) {
    printerr "Error: $err"
    System.exit(1)
}

def diskConfigs = args.size() > 0 && args[0] == '--prod' ? PROD_DISK_CONFIGS : TEST_DISK_CONFIGS

def snapshots = out.tokenize('\n' as char)
        .collect { String line ->
            List<String> lineItems = line.tokenize(',')
            ['snapshotName': lineItems[0], 'srcDisk': lineItems[1], 'status': lineItems[2]]
        }
        .findAll { snapshot ->
            snapshot.status == 'READY'
            diskConfigs.any { disk -> snapshot.srcDisk.contains(disk.oldDiskName) }
        }

def diskToSnapshots = snapshots.groupBy { it.srcDisk }
        .collect { k, v ->
            def latestSnapshot = v.sort { it.snapshotName }.last()
            def diskConfig = diskConfigs.find { latestSnapshot.srcDisk.contains(it.oldDiskName) }
            diskConfig.snapshotName = latestSnapshot.snapshotName
            diskConfig
        }

diskToSnapshots.each { newDiskConfig ->
    println """gcloud compute disks create ${newDiskConfig.newPdDiskName} \\
  --size=${newDiskConfig.size} \\
  --source-snapshot=${newDiskConfig.snapshotName} \\
  --type=${newDiskConfig.type} \\
  --resource-policies=$RESOURCE_POLICIES \\
  --labels=${newDiskConfig.labels.collect { "$it" }.join(',')} \\
  --zone=$ZONE
"""
}
