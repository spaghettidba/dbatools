function Get-DbaUserPermission {
    <#
    .SYNOPSIS
        Displays detailed permissions information for the server and database roles and securables.

    .DESCRIPTION
        This command will display all server logins, server level securables, database logins and database securables.

        DISA STIG implementors will find this command useful as it uses Permissions.sql provided by DISA.

        Note that if you Ctrl-C out of this command and end it prematurely, it will leave behind a STIG schema in tempdb.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER ExcludeSystemDatabase
        Allows you to suppress output on system databases

    .PARAMETER IncludePublicGuest
        Allows you to include output for public and guest grants.

    .PARAMETER IncludeSystemObjects
        Allows you to include output on sys schema objects.

    .PARAMETER ExcludeSecurables
        Allows you to exclude object-level permissions from the output, and only return role permission(s).

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Security, User
        Author: Brandon Abshire, netnerds.net | Josh Smith

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaUserPermission

    .EXAMPLE
        PS C:\> Get-DbaUserPermission -SqlInstance sql2008, sqlserver2012

        Check server and database permissions for servers sql2008 and sqlserver2012.

    .EXAMPLE
        PS C:\> Get-DbaUserPermission -SqlInstance sql2008 -Database TestDB

        Check server and database permissions on server sql2008 for only the TestDB database

    .EXAMPLE
        PS C:\> Get-DbaUserPermission -SqlInstance sql2008 -Database TestDB -IncludePublicGuest -IncludeSystemObjects

        Check server and database permissions on server sql2008 for only the TestDB database,
        including public and guest grants, and sys schema objects.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$ExcludeSystemDatabase,
        [switch]$IncludePublicGuest,
        [switch]$IncludeSystemObjects,
        [switch]$ExcludeSecurables,
        [switch]$EnableException
    )

    begin {
        $removeStigSQL = "       BEGIN TRY DROP FUNCTION STIG.server_effective_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.server_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.members_of_server_role END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.server_roles_of END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.server_role_members END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.database_effective_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.database_permissions END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.members_of_db_role END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP FUNCTION STIG.database_roles_of END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP VIEW STIG.database_role_members END TRY BEGIN CATCH END CATCH;
                       GO
                       BEGIN TRY DROP SCHEMA STIG END TRY BEGIN CATCH END CATCH;
                       GO"


        $serverSQL = "SELECT  'SERVER LOGINS' AS Type ,
                                    sl.name AS Member ,
                                    ISNULL(srm.Role, 'None') AS [Role/Securable/Class] ,
                                    ' ' AS [Schema/Owner] ,
                                    ' ' AS [Securable] ,
                                    ' ' AS [Grantee Type] ,
                                    ' ' AS [Grantee] ,
                                    ' ' AS [Permission] ,
                                    ' ' AS [State] ,
                                    ' ' AS [Grantor] ,
                                    ' ' AS [Grantor Type] ,
                                    ' ' AS [Source View]
                            FROM    master.sys.syslogins sl
                                    LEFT JOIN tempdb.[STIG].[server_role_members] srm ON sl.name = srm.Member
                            WHERE   sl.name NOT LIKE 'NT %'
                                    AND sl.name NOT LIKE '##%'"

        $dbSQL = "SELECT  'DB ROLE MEMBERS' AS type ,
                                Member ,
                                ISNULL(Role, 'None') AS [Role/Securable/Class],
                                ' ' AS [Schema/Owner] ,
                                ' ' AS [Securable] ,
                                ' ' AS [Grantee Type] ,
                                ' ' AS [Grantee] ,
                                ' ' AS [Permission] ,
                                ' ' AS [State] ,
                                ' ' AS [Grantor] ,
                                ' ' AS [Grantor Type] ,
                                ' ' AS [Source View]
                        FROM    tempdb.[STIG].[database_role_members]"

        # append unions to get securables if not excluded:
        if (-not $ExcludeSecurables) {

            $serverSQL = $serverSQL + "
                            UNION
                            SELECT  'SERVER SECURABLES' AS Type ,
                                    sl.name ,
                                    sp.[Securable Class] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    ' ' ,
                                    sp.[Securable] ,
                                    sp.[Grantee Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.Grantee ,
                                    sp.Permission COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.State COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.Grantor ,
                                    sp.[Grantor Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                    sp.[Source View]
                            FROM    master.sys.syslogins sl
                                    LEFT JOIN tempdb.[STIG].[server_permissions] sp ON sl.name = sp.Grantee
                            WHERE   sl.name NOT LIKE 'NT %'
                                    AND sl.name NOT LIKE '##%';"

            $dbSQL = $dbSQL + "
                        UNION
                        SELECT DISTINCT
                                'DB SECURABLES' AS Type ,
                                ISNULL(drm.member, 'None') AS [Role/Securable/Class] ,
                                dp.[Securable Type or Class] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.[Schema/Owner] ,
                                dp.Securable ,
                                dp.[Grantee Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.Grantee ,
                                dp.Permission COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.State COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.Grantor ,
                                dp.[Grantor Type] COLLATE SQL_Latin1_General_CP1_CI_AS ,
                                dp.[Source View]
                        FROM    tempdb.[STIG].[database_role_members] drm
                                FULL JOIN tempdb.[STIG].[database_permissions] dp ON ( drm.Member = dp.Grantee
                                                                                      OR drm.Role = dp.Grantee
                                                                                     )
                        WHERE    dp.Grantor IS NOT NULL
                                AND dp.Grantee NOT IN ('public', 'guest')
                                AND [Schema/Owner] <> 'sys'"
        }

        if ($IncludePublicGuest) { $dbSQL = $dbSQL.Replace("AND dp.Grantee NOT IN ('public', 'guest')", "") }
        if ($IncludeSystemObjects) { $dbSQL = $dbSQL.Replace("AND [Schema/Owner] <> 'sys'", "") }

    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10 -AzureUnsupported
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases
            $tempdb = $server.Databases['tempdb']

            if ($Database) {
                $dbs = $dbs | Where-Object { $Database -contains $_.Name }
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            if ($ExcludeSystemDatabase) {
                $dbs = $dbs | Where-Object IsSystemObject -eq $false
            }

            Write-Message -Level Verbose -Message "Reading stig.sql"
            $sqlFile = Join-DbaPath -Path $script:PSModuleRoot -ChildPath "bin", "stig.sql"
            $sql = [System.IO.File]::ReadAllText("$sqlFile")

            try {
                Write-Message -Level Verbose -Message "Removing STIG schema if it still exists from previous run"
                $tempdb.ExecuteNonQuery($removeStigSQL)
                Write-Message -Level Verbose -Message "Creating STIG schema customized for master database"
                $createStigSQL = $sql.Replace("<TARGETDB>", 'master')
                $tempdb.ExecuteNonQuery($createStigSQL)
                Write-Message -Level Verbose -Message "Building data table for server objects"
                $serverDT = $tempdb.Query($serverSQL)
                foreach ($row in $serverDT) {
                    [PSCustomObject]@{
                        ComputerName       = $server.ComputerName
                        InstanceName       = $server.ServiceName
                        SqlInstance        = $server.DomainInstanceName
                        Object             = 'SERVER'
                        Type               = $row.Type
                        Member             = $row.Member
                        RoleSecurableClass = $row.'Role/Securable/Class'
                        SchemaOwner        = $row.'Schema/Owner'
                        Securable          = $row.Securable
                        GranteeType        = $row.'Grantee Type'
                        Grantee            = $row.Grantee
                        Permission         = $row.Permission
                        State              = $row.State
                        Grantor            = $row.Grantor
                        GrantorType        = $row.'Grantor Type'
                        SourceView         = $row.'Source View'
                    }
                }
            } catch {
                Stop-Function -Message "Failed to create or use STIG schema on $instance" -ErrorRecord $_ -Target $instance -Continue
            }

            foreach ($db in $dbs) {
                Write-Message -Level Verbose -Message "Processing $db on $instance"

                if ($db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "The database $db on $instance is not accessible. Skipping."
                    continue
                }

                try {
                    Write-Message -Level Verbose -Message "Removing STIG schema if it still exists from previous run"
                    $tempdb.ExecuteNonQuery($removeStigSQL)
                    Write-Message -Level Verbose -Message "Creating STIG schema customized for current database"
                    $createStigSQL = $sql.Replace("<TARGETDB>", $db.Name)
                    Write-Message -Level Verbose -Message "Length of createStigSQL: $($createStigSQL.Length)"
                    $tempdb.ExecuteNonQuery($createStigSQL)
                    Write-Message -Level Verbose -Message "Building data table for database objects"
                    $dbDT = $db.Query($dbSQL)
                    foreach ($row in $dbDT) {
                        [PSCustomObject]@{
                            ComputerName       = $server.ComputerName
                            InstanceName       = $server.ServiceName
                            SqlInstance        = $server.DomainInstanceName
                            Object             = $db.Name
                            Type               = $row.Type
                            Member             = $row.Member
                            RoleSecurableClass = $row.'Role/Securable/Class'
                            SchemaOwner        = $row.'Schema/Owner'
                            Securable          = $row.Securable
                            GranteeType        = $row.'Grantee Type'
                            Grantee            = $row.Grantee
                            Permission         = $row.Permission
                            State              = $row.State
                            Grantor            = $row.Grantor
                            GrantorType        = $row.'Grantor Type'
                            SourceView         = $row.'Source View'
                        }
                    }
                } catch {
                    Stop-Function -Message "Failed to create or use STIG schema for database $db on $instance" -ErrorRecord $_ -Target $instance -Continue
                }
            }

            Write-Message -Level Verbose -Message "Removing STIG schema from tempdb"
            $tempdb.ExecuteNonQuery($removeStigSQL)
        }
    }
}