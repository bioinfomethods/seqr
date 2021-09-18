@GrabConfig(systemClassLoader = true)
// systemClassLoader is needed to ensure DriverManager can find the DB driver
@Grab('info.picocli:picocli-groovy')
@Grab('org.postgresql:postgresql')
@Grab('io.github.http-builder-ng:http-builder-ng-core')
@picocli.groovy.PicocliScript
@picocli.CommandLine.Command(name = "dump_tables.groovy",
        mixinStandardHelpOptions = true,  // add --help and --version options
        version = "0.0.1",
        description = """
This script dumps table into output SQL statements.
""")
import groovy.sql.Sql
import groovy.transform.Field
import picocli.CommandLine

import java.nio.file.Files
import java.sql.Connection
import java.sql.Date as SqlDate
import java.sql.DriverManager
import java.sql.Timestamp as SqlTimestamp

@CommandLine.Option(names = ['-o', '--output'], arity = '1', required = false, defaultValue = 'dump.sql', description = 'Output SQL file, defaults to dump.sql')
@Field File outputFile = new File('dump.sql')

@CommandLine.Parameters(index = '0', arity = '1', paramLabel = 'dbConnStr', defaultValue = 'jdbc:postgresql://localhost:5432/postgres?user=postgres', description = 'DB JDBC URL, defaults to jdbc:postgresql://localhost:5432/postgres?user=postgres')
@Field String dbConnStr

@CommandLine.Spec @Field CommandLine.Model.CommandSpec spec
println "${spec.options().collect { "${it.longestName()}=${it.value}" }.join('\n')}"

Properties props = new Properties()
props.setProperty('readOnly', 'true')
Class.forName("org.postgresql.Driver")
Connection dbConn = DriverManager.getConnection(dbConnStr, props)
Sql db = new Sql(dbConn)

def tables = [
        [tableName: 'auth_group', columns: '*', whereClause: null, orderByClause: 'ORDER BY name, id', newTableName: null],
//        [tableName: 'django_content_type', columns: '*', orderByClause: 'ORDER BY app_label, model, id', newTableName: null],
        [tableName: 'auth_permission ap', columns: '*', whereClause: null, orderByClause: 'ORDER BY content_type_id, name, id', newTableName: null],
        [tableName: 'auth_user_groups', columns: '*', whereClause: null, orderByClause: 'ORDER BY group_id, user_id, id', newTableName: null],
        [tableName: 'auth_group_permissions', columns: '*', whereClause: null, orderByClause: 'ORDER BY group_id, permission_id, id', newTableName: null],
        [tableName: 'auth_user_user_permissions', columns: '*', whereClause: null, orderByClause: 'ORDER BY user_id, permission_id, id', newTableName: null],
        [tableName: 'guardian_groupobjectpermission', columns: '*', whereClause: null, orderByClause: 'ORDER BY group_id, permission_id, id', newTableName: null],
        [tableName: 'guardian_userobjectpermission', columns: '*', whereClause: null, orderByClause: 'ORDER BY content_type_id, permission_id, user_id, id', newTableName: null],
        [tableName: 'auth_user', columns: '*', whereClause: null, orderByClause: 'ORDER BY username, id', newTableName: null],
        [
                tableName    : 'seqr_project',
                columns      : 'id, name, description, genome_version, disable_staff_access, last_accessed_date, can_edit_group_id, can_view_group_id, owners_group_id',
                whereClause  : null,
                orderByClause: 'ORDER BY guid, id', newTableName: 'core_project'
        ],
]

def ignoreColumns = [
        'SEQ',
        'VERSION'
]

def escapeValue(String value) {
    value.replaceAll("'", "''")
}

Files.deleteIfExists(outputFile.toPath())

outputFile.withWriterAppend('UTF-8') { BufferedWriter bw ->
    bw.writeLine('\\SET ON_ERROR_STOP ON')
    bw.writeLine('BEGIN;')

    tables.each { table ->
        String sourceTableName = table.tableName
        String targetTableName = table.newTableName ?: sourceTableName
        String columns = table.columns
        String where = table.whereClause ?: ''
        String orderByClause = table.orderByClause
        String outputFileName = table.outputFileName

        def query = "SELECT $columns FROM $sourceTableName $where $orderByClause".toString()
        def rows = db.rows(query)
        if (rows.empty) {
            return
        }

        println "Applying query [$query] output to file ${outputFile.toString()}"

        String insertColumnsStr = "INSERT INTO ${targetTableName.toLowerCase()} (${rows.first().keySet().findAll { !ignoreColumns.contains(it) }.collect { it.toLowerCase() }.join(', ')})"
        rows.each { row ->
            def rowValuesStr = []
            row.entrySet().findAll { e -> !ignoreColumns.contains(e.key) }.each { entry ->
                def value = entry.value
                if (value instanceof SqlDate || value instanceof SqlTimestamp) {
                    rowValuesStr << "DATE '${value.format('yyyy-MM-dd')}'"
                } else if (value instanceof String) {
                    rowValuesStr << "'${escapeValue(value)}'"
                } else if (value instanceof Number) {
                    rowValuesStr << value
                } else if (value instanceof Boolean) {
                    rowValuesStr << value ? 'TRUE' : 'FALSE'
                } else if (value == null) {
                    rowValuesStr << 'NULL'
                } else {
//                    println "[${value.getClass()}]"
                    rowValuesStr << "'${escapeValue(value)}'"
                }
            }
            bw.println "${insertColumnsStr} VALUES(${rowValuesStr.join(', ')});"
        }
    }

    bw.writeLine('COMMIT;')
}
