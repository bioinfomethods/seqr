/**
 * Example:
 * groovy $PROJECT_DIR/scripts/seqr_support_email.groovy -sh localhost -sp 1025 -e 'tommy.li@mcri.edu.au' -db $POSTGRES_SEQRPRODB_DB_JDBC_URL --staff --super $PROJECT_DIR/scripts/maintenance_email.txt
 */

import groovy.sql.Sql
import groovy.transform.Field
import picocli.CommandLine

import javax.mail.*
import javax.mail.internet.InternetAddress
import javax.mail.internet.MimeMessage
@GrabConfig(systemClassLoader = true)
// systemClassLoader is needed to ensure DriverManager can find the DB driver
@Grab('com.sun.mail:javax.mail')
@Grab('info.picocli:picocli-groovy')
@Grab('org.postgresql:postgresql')
@picocli.groovy.PicocliScript
@picocli.CommandLine.Command(name = "seqr_support_email",
        mixinStandardHelpOptions = true,  // add --help and --version options
        version = "0.0.1",
        description = """
This script sends an email (provided from a txt file) to Seqr users.  Used for support notifications.
All recipients are in BCC email field.
""")
import java.sql.Connection
import java.sql.DriverManager

@CommandLine.Parameters(index = '0', arity = '1', paramLabel = 'emailFile', defaultValue = 'email.txt', description = 'Path to email file')
@Field File emailFile

@CommandLine.Option(arity = '1', names = ['-db', '--seqrDb'], defaultValue = 'jdbc:postgresql://localhost:15432/seqrdb?user=postgres', description = 'Seqr DB JDBC URL')
@Field String seqrDbConnStr
@CommandLine.Option(arity = '1', names = ['-sh', '--smtpHost'], defaultValue = 'localhost', description = 'Email SMTP Host')
@Field String smtpHost
@CommandLine.Option(arity = '1', names = ['-sp', '--smtpPort'], defaultValue = '1025', description = 'Email SMTP Port')
@Field String smtpPort
@CommandLine.Option(arity = '0', names = ['--smtps'], defaultValue = 'false', fallbackValue = 'false', description = 'Use SMTPS secure connection to SMTP server')
@Field boolean useSmtps
@CommandLine.Option(arity = '1', names = ['-sc', '--smtpCredentials'], defaultValue = 'username=password', description = 'Email SMTP Credentials')
@Field Map<String, String> smtpCreds
@CommandLine.Option(arity = '0', names = ['-s', '--staff'], defaultValue = 'false', fallbackValue = 'false', description = 'Only email Seqr staff users')
@Field boolean staffOnly
@CommandLine.Option(arity = '0', names = ['-su', '--super'], defaultValue = 'false', fallbackValue = 'false', description = 'Only email Seqr superusers')
@Field boolean superOnly
@CommandLine.Option(arity = '0', names = ['-es', '--emailSubject'], defaultValue = 'Seqr Notification', description = 'Email subject field')
@Field String emailSubject
@CommandLine.Option(arity = '1', names = ['-fe', '--fromEmail'], defaultValue = 'seqr@seqr.mcri.edu.au', description = 'From address of email')
@Field String fromEmail
@CommandLine.Option(arity = '0..*', names = ['-e', '--emails'], split = ',', description = 'Additional emails to include into BCC, handy for testing')
@Field List<String> emails
@CommandLine.Option(arity = '0..*', names = ['-ae', '--adminEmails'], defaultValue = 'tommy.li@mcri.edu.au, simon.sadedin@vcgs.org.au', split = ',', description = 'Seqr admin emails used in replyTo email field')
@Field List<String> adminEmails

@CommandLine.Spec @Field CommandLine.Model.CommandSpec spec
println "${spec.options().collect { "${it.longestName()}=${it.value}" }.join('\n')}"

Class.forName("org.postgresql.Driver")
Connection seqrDbConn = DriverManager.getConnection(seqrDbConnStr, ['readOnly': 'true'] as Properties)
Sql seqrDb = new Sql(seqrDbConn)

def allSeqrUsers = seqrDb.rows("""
WITH user_group AS (
  select au.id user_id, au.email, au.first_name, au.last_name, ag.id group_id, au.is_superuser, au.is_staff
  from auth_user au
    join auth_user_groups aug ON aug.user_id = au.id
    join auth_group ag ON ag.id = aug.group_id
  WHERE au.is_active IS TRUE
),
proj_manager AS (
  SELECT ug.*, sp.guid project_guid, sp.description
  FROM user_group ug
    JOIN seqr_project sp ON sp.can_edit_group_id = ug.group_id
),
proj_collaborator AS (
  SELECT ug.*, sp.guid project_guid, sp.description
  FROM user_group ug
    JOIN seqr_project sp ON sp.can_view_group_id = ug.group_id
),
r AS (
  SELECT DISTINCT c.user_id, c.email, c.first_name, c.last_name, COALESCE(c.is_staff, m.is_staff) is_staff, COALESCE(c.is_superuser, m.is_superuser) is_superuser, CASE WHEN m.project_guid IS NULL THEN 'N' ELSE 'Y' END project_manager_yn, c.project_guid, c.description
  FROM proj_collaborator c
    LEFT JOIN proj_manager m ON m.user_id = c.user_id
)
SELECT *
FROM r
ORDER BY r.project_guid, r.project_manager_yn DESC, r.email
""")

def staffFilter = { seqrUser ->
    staffOnly ? seqrUser.is_staff : true
}

def superUserFilter = { seqrUser ->
    superOnly ? seqrUser.is_superuser : true
}

List<String> filteredSeqr = allSeqrUsers
        .findAll(staffFilter)
        .findAll(superUserFilter)
        .collect { it.email }
List<String> recipients = (filteredSeqr + (emails ?: [])).unique()

Properties mailProps = [
        'mail.smtp.host': smtpHost,
        'mail.smtp.port': smtpPort,
        'mail.debug'    : 'false',
] as Properties

Properties secureMailProps = [
        'mail.transport.protocol': 'smtps',
        'mail.smtps.auth'        : 'true',
        'mail.smtps.host'        : smtpHost,
        'mail.smtp.port'         : smtpPort,
        'mail.debug'             : 'false',
] as Properties

String username = smtpCreds.keySet().first()
String password = smtpCreds.values().first()
Authenticator auth = new Authenticator() {
    @Override
    PasswordAuthentication getPasswordAuthentication() {
        return new PasswordAuthentication(username, password)
    }
}
Session session = Session.getDefaultInstance(useSmtps ? secureMailProps : mailProps, auth)

MimeMessage message = new MimeMessage(session)
message.reply(false)
message.setReplyTo(adminEmails.collect { new InternetAddress(it) } as Address[])
message.setFrom(new InternetAddress(fromEmail))
Transport transport = session.getTransport()
transport.connect(smtpHost, smtpPort as Integer, username, password)

message.addRecipients(Message.RecipientType.BCC, recipients.collect { new InternetAddress(it) } as Address[])
message.setSubject(emailSubject)
message.setContent(emailFile.text, 'text/plain')
transport.sendMessage(message, message.getAllRecipients())
