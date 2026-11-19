$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Web
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CacheDirectory = Join-Path $env:LOCALAPPDATA 'CO-Emissionsrechner'
$script:CacheFile = Join-Path $script:CacheDirectory 'oekobaudat.csv'
$script:CacheMetadataFile = Join-Path $script:CacheDirectory 'oekobaudat.metadata.json'
$script:ReleasePageUrl = 'https://www.oekobaudat.de/service/downloads.html'
$script:DataSource = 'OEKOBAUDAT-CSV-Export, EN 15804+A2, Modul A1-A3'
$script:Dataset = $null
$script:UserImportRecords = @()
$script:UserImportBatches = @()
$script:UserImportStateLoaded = $false
$script:PendingUserImports = @{}
$script:CombinedCatalogIndex = $null
$script:UserImportStoreFile = Join-Path $script:CacheDirectory 'user-imports.json'
$script:UserImportMaxBytes = 5 * 1024 * 1024
$script:UserImportMaxRows = 10000
$script:UserImportMaxStoredRecords = 25000
$script:UserImportMaxStoreBytes = 25 * 1024 * 1024
$script:UserImportLicenseStatus = 'user-attested-not-independently-verified'
$script:UserImportUsageNotice = 'Benutzerimport: Quelle und Nutzungsrechte wurden vom Importierenden angegeben, aber nicht unabhängig geprüft.'
$script:RetrievedAt = $null
$script:DataWarning = $null
$script:SourceMetadata = $null
$script:CacheStatus = 'not-loaded'
$script:CatalogManifest = $null
$script:CatalogIndex = $null
$script:CatalogStatus = 'not-loaded'
$script:CatalogLicenseStatus = 'reuse-terms-not-independently-verified'
$script:CatalogUsageNotice = 'ÖKOBAUDAT ist öffentlich zugänglich; eine pauschale Lizenz zur Weitergabe wurde nicht verifiziert. Der Katalog wird nicht in das Repository oder Frontend kopiert.'
$script:MaterialAliasGroups = @(
    @('Kalksandstein', 'Kalksandstein-Mauerwerk', 'Kalksandsteinmauerwerk', 'calcium silicate brick', 'sand-lime brick'),
    @('Holzfaserdämmstoff', 'Holzfaser', 'wood fibre insulation', 'wood fiber insulation'),
    @('Mineralwolle', 'Steinwolle', 'Glaswolle', 'mineral wool', 'rock wool', 'glass wool'),
    @('Zellulosefaser', 'Zellulosedämmung', 'cellulose insulation'),
    @('expandiertes Polystyrol', 'expanded polystyrene', 'EPS'),
    @('extrudiertes Polystyrol', 'extruded polystyrene', 'XPS'),
    @('Ziegel', 'Mauerziegel', 'Backstein', 'brick', 'clay brick'),
    @('Gipskarton', 'Gipsplatte', 'gypsum board', 'drywall'),
    @('Beton', 'concrete'),
    @('Mörtel', 'mortar'),
    @('Stahl', 'steel'),
    @('Aluminium', 'aluminum', 'aluminium'),
    @('Glas', 'glass'),
    @('Holz', 'timber', 'wood')
)
$script:ManufacturerQueryTerms = @(
    'Röben', 'Wieneberger', 'Wienerberger', 'Heinze', 'Bundesverband Ziegel',
    'Haro', 'HARO', 'Bauwerk', 'bembé', 'Boen', 'Drüsedau', 'Grunreben',
    'Hain', 'Trumpf', 'ter Hürne', 'Holz Reinlein', 'Wimmer',
    'Schotten und Hansen', 'Meisterwerke', 'MeisterWerke', 'Parador',
    'Parkett-Herter', 'Kährs', 'Rockwoll', 'ROCKWOOL', 'Würth',
    'Casea', 'formula', 'one Mineral', 'Knauf'
)

function Send-Response {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode,
        [string]$ContentType,
        [byte[]]$Body
    )

    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = $ContentType
    $Context.Response.ContentEncoding = [System.Text.Encoding]::UTF8
    $Context.Response.ContentLength64 = $Body.Length
    $Context.Response.Headers['X-Content-Type-Options'] = 'nosniff'
    $Context.Response.OutputStream.Write($Body, 0, $Body.Length)
    $Context.Response.Close()
}

function Send-Json {
    param(
        [System.Net.HttpListenerContext]$Context,
        [int]$StatusCode,
        [object]$Value
    )

    $json = ConvertTo-Json -InputObject $Value -Depth 8 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    Send-Response -Context $Context -StatusCode $StatusCode -ContentType 'application/json; charset=utf-8' -Body $bytes
}

function Assert-SameOriginImportRequest {
    param([System.Net.HttpListenerContext]$Context)

    $origin = $Context.Request.Headers['Origin']
    if ([string]::IsNullOrWhiteSpace($origin)) {
        return
    }
    $originUri = $null
    if (-not [uri]::TryCreate($origin, [System.UriKind]::Absolute, [ref]$originUri)) {
        throw 'Ungültiger Origin-Header.'
    }
    $requestUri = $Context.Request.Url
    if ($originUri.Scheme -ne $requestUri.Scheme -or
        $originUri.Host -ne $requestUri.Host -or
        $originUri.Port -ne $requestUri.Port) {
        throw 'Importe sind nur über denselben App-Ursprung zulässig.'
    }
}

function Read-BoundedRequestBytes {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [long]$MaximumBytes
    )

    if ($Request.ContentLength64 -gt $MaximumBytes) {
        $exception = [System.IO.InvalidDataException]::new('Die Anfrage überschreitet das Größenlimit.')
        $exception.Data['StatusCode'] = 413
        throw $exception
    }
    $memory = [System.IO.MemoryStream]::new()
    $buffer = [byte[]]::new(8192)
    try {
        while (($read = $Request.InputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $read -gt $MaximumBytes) {
                $exception = [System.IO.InvalidDataException]::new('Die Anfrage überschreitet das Größenlimit.')
                $exception.Data['StatusCode'] = 413
                throw $exception
            }
            $memory.Write($buffer, 0, $read)
        }
        return ,$memory.ToArray()
    }
    finally {
        $memory.Dispose()
    }
}

function Read-StrictUtf8RequestText {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [long]$MaximumBytes
    )

    $bytes = Read-BoundedRequestBytes -Request $Request -MaximumBytes $MaximumBytes
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    return $utf8.GetString($bytes)
}

function Get-Field {
    param(
        [string[]]$Fields,
        [hashtable]$Columns,
        [string]$Name
    )

    if (-not $Columns.ContainsKey($Name)) {
        return ''
    }

    $index = $Columns[$Name]
    if ($index -ge $Fields.Length) {
        return ''
    }

    return ([string]$Fields[$index]).Trim().Trim("'")
}

function Normalize-MaterialSearchText {
    param([string]$Value)

    $normalized = $Value.ToLowerInvariant().Replace('ß', 'ss').Normalize([System.Text.NormalizationForm]::FormD)
    $builder = [System.Text.StringBuilder]::new()
    foreach ($character in $normalized.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -eq [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            continue
        }
        [void]$builder.Append($character)
    }

    return ([regex]::Replace($builder.ToString(), '[^a-z0-9]+', ' ')).Trim()
}

function Test-ContainsMaterialTerm {
    param(
        [string]$Query,
        [string]$Term
    )

    $queryKey = Normalize-MaterialSearchText -Value $Query
    $termKey = Normalize-MaterialSearchText -Value $Term
    if ([string]::IsNullOrWhiteSpace($queryKey) -or [string]::IsNullOrWhiteSpace($termKey)) {
        return $false
    }

    return " $queryKey ".Contains(" $termKey ")
}

function Get-MaterialQueryTerms {
    param([string]$Query)

    $terms = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $original = $Query.Trim()
    if (-not [string]::IsNullOrWhiteSpace($original)) {
        $terms.Add($original)
        [void]$seen.Add((Normalize-MaterialSearchText -Value $original))
    }
    if ($script:ManufacturerQueryTerms -contains $original) {
        return $terms.ToArray()
    }

    foreach ($group in $script:MaterialAliasGroups) {
        $groupMatches = $false
        foreach ($alias in $group) {
            if (Test-ContainsMaterialTerm -Query $original -Term $alias) {
                $groupMatches = $true
                break
            }
        }
        if (-not $groupMatches) {
            continue
        }

        foreach ($alias in $group) {
            $key = Normalize-MaterialSearchText -Value $alias
            if ($seen.Add($key)) {
                $terms.Add($alias)
            }
            if ($terms.Count -ge 12) {
                return $terms.ToArray()
            }
        }
    }

    return $terms.ToArray()
}

function Test-MaterialSearchTerm {
    param(
        [string]$Name,
        [string]$Category,
        [string]$Owner,
        [string]$Term
    )

    if ($script:ManufacturerQueryTerms -contains $Term) {
        $pattern = '(?<![\p{L}\p{N}])' + [regex]::Escape($Term) + '(?![\p{L}\p{N}])'
        return [regex]::IsMatch("$Name $Category $Owner", $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }

    if ($Name.IndexOf($Term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $Category.IndexOf($Term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        return $true
    }

    $ownerPattern = '(?<![\p{L}\p{N}])' + [regex]::Escape($Term) + '(?![\p{L}\p{N}])'
    return [regex]::IsMatch($Owner, $ownerPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Get-SearchTermPriority {
    param(
        [string]$Name,
        [string[]]$QueryTerms
    )

    for ($index = 0; $index -lt $QueryTerms.Length; $index++) {
        $term = $QueryTerms[$index]
        if ($Name.Equals($term, [System.StringComparison]::OrdinalIgnoreCase)) {
            return ($index * 4)
        }
        if ($Name.StartsWith("$term ", [System.StringComparison]::OrdinalIgnoreCase)) {
            return ($index * 4) + 1
        }
        if ($Name.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return ($index * 4) + 2
        }
    }

    return [int]::MaxValue
}

function Get-RecordMatchedTerms {
    param(
        [object]$Record,
        [string[]]$QueryTerms
    )

    return @($QueryTerms | Where-Object {
        Test-MaterialSearchTerm -Name ([string]$Record.Name) -Category ([string]$Record.Category) -Owner ([string]$Record.Owner) -Term $_
    })
}

function Build-MaterialCatalogIndex {
    param([object[]]$Records)

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        $entries.Add([pscustomobject]@{
            Record = $record
            Name = [string]$record.Name
            Category = [string]$record.Category
            Owner = [string]$record.Owner
        })
    }

    return ,$entries.ToArray()
}

function Get-IndexedRecordMatchedTerms {
    param(
        [object]$Entry,
        [string[]]$QueryTerms
    )

    return @($QueryTerms | Where-Object {
        Test-MaterialSearchTerm -Name $Entry.Name -Category $Entry.Category -Owner $Entry.Owner -Term $_
    })
}

function Find-MaterialRecords {
    param(
        [object[]]$Records,
        [string]$Query,
        [object[]]$Index
    )

    $queryTerms = @(Get-MaterialQueryTerms -Query $Query)
    $matchedTermSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $matches = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Index) {
        foreach ($entry in $Index) {
            $recordTerms = @(Get-IndexedRecordMatchedTerms -Entry $entry -QueryTerms $queryTerms)
            if ($recordTerms.Count -eq 0) {
                continue
            }

            $matches.Add($entry.Record)
            foreach ($term in $recordTerms) {
                [void]$matchedTermSet.Add($term)
            }
        }
    }
    else {
        foreach ($record in $Records) {
            $recordTerms = @(Get-RecordMatchedTerms -Record $record -QueryTerms $queryTerms)
            if ($recordTerms.Count -eq 0) {
                continue
            }

            $matches.Add($record)
            foreach ($term in $recordTerms) {
                [void]$matchedTermSet.Add($term)
            }
        }
    }

    return [pscustomobject]@{
        QueryTerms = $queryTerms
        MatchedTerms = @($queryTerms | Where-Object { $matchedTermSet.Contains($_) })
        Records = $matches.ToArray()
    }
}

function Get-OfficialExportInfo {
    param([Parameter(Mandatory)][string]$Html)

    $pattern = '(?is)<a\b[^>]*href="(?<url>https://www\.oekobaudat\.de/OEKOBAU\.DAT/resource/datastocks/(?<id>[a-f0-9-]+)/exportCSV(?:\?[^"]*)?)"[^>]*>(?<text>.*?)</a>'
    $candidates = [System.Collections.Generic.List[object]]::new()
    foreach ($match in [regex]::Matches($Html, $pattern)) {
        $url = [System.Net.WebUtility]::HtmlDecode($match.Groups['url'].Value)
        if ($url -match '(?i)decimalSeparator=comma') {
            continue
        }

        $text = [System.Net.WebUtility]::HtmlDecode(($match.Groups['text'].Value -replace '<[^>]+>', ' ')).Trim()
        $release = [regex]::Match($text, '(?i)ÖKOBAUDAT\s+(?<release>20\d{2}-[IVX]+)')
        if (-not $release.Success) {
            continue
        }

        $candidates.Add([pscustomobject]@{
            Url = $url
            DataStockId = $match.Groups['id'].Value
            Release = $release.Groups['release'].Value
            IsPreferred = ($text -match 'Punkt als Dezimaltrenner')
        })
    }

    $selected = $candidates | Where-Object { $_.IsPreferred } | Select-Object -First 1
    if ($null -eq $selected) {
        $selected = $candidates | Select-Object -First 1
    }
    if ($null -eq $selected) {
        throw 'Auf der offiziellen ÖKOBAUDAT-Downloadseite wurde kein eindeutig benannter CSV-Export mit Datenstand gefunden.'
    }

    return [pscustomobject]@{
        SourceName = 'ÖKOBAUDAT'
        Release = $selected.Release
        DataStockId = $selected.DataStockId
        DownloadUrl = $selected.Url
        ReleasePageUrl = $script:ReleasePageUrl
        Format = 'CSV, Dezimalpunkt'
        Modules = 'A1-A3'
        Standard = 'EN 15804+A2'
    }
}

function Test-OekoCsvFile {
    param([Parameter(Mandatory)][string]$Path)

    $encoding = [System.Text.Encoding]::GetEncoding(28591)
    $parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($Path, $encoding)
    $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
    $parser.SetDelimiters(';')
    $parser.HasFieldsEnclosedInQuotes = $true
    $parser.TrimWhiteSpace = $false

    try {
        $headers = $parser.ReadFields()
        $columns = @{}
        for ($index = 0; $index -lt $headers.Length; $index++) {
            $columns[$headers[$index]] = $index
        }
        foreach ($required in @('UUID', 'Version', 'Name (de)', 'GWPtotal (A2)', 'Konformitaet', 'Modul')) {
            if (-not $columns.ContainsKey($required)) {
                throw "Der ÖKOBAUDAT-CSV-Export enthält nicht die erwartete Spalte '$required'."
            }
        }

        while (-not $parser.EndOfData) {
            $fields = $parser.ReadFields()
            if ($null -eq $fields) {
                continue
            }
            if ((Get-Field -Fields $fields -Columns $columns -Name 'Konformitaet') -match 'EN 15804\+A2' -and
                (Get-Field -Fields $fields -Columns $columns -Name 'Modul') -eq 'A1-A3' -and
                -not [string]::IsNullOrWhiteSpace((Get-Field -Fields $fields -Columns $columns -Name 'Name (de)'))) {
                return $true
            }
        }
    }
    finally {
        $parser.Close()
    }

    throw 'Der ÖKOBAUDAT-CSV-Export enthält keine Datensätze für EN 15804+A2, Modul A1-A3.'
}

function Read-OekoCacheMetadata {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{
            MetadataError = $_.Exception.Message
        }
    }
}

function Write-OekoCacheMetadata {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Metadata
    )

    $temporaryPath = "$Path.download"
    $json = ConvertTo-Json -InputObject $Metadata -Depth 5
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
        Move-FileAtomically -Source $temporaryPath -Destination $Path
    }
    catch {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Move-FileAtomically {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        $backupPath = "$Destination.$([guid]::NewGuid().ToString('N')).bak"
        [System.IO.File]::Replace($Source, $Destination, $backupPath)
        if (Test-Path -LiteralPath $backupPath) {
            Remove-Item -LiteralPath $backupPath -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $backupPath) {
                Write-Warning "Temporäre Sicherung konnte nicht entfernt werden: $backupPath"
            }
        }
        return
    }

    [System.IO.File]::Move($Source, $Destination)
}

function Write-CatalogManifest {
    param([Parameter(Mandatory)][int]$RecordCount)

    $catalogDirectory = Join-Path $script:CacheDirectory 'catalog'
    if (-not (Test-Path -LiteralPath $catalogDirectory)) {
        New-Item -ItemType Directory -Path $catalogDirectory -Force | Out-Null
    }

    $sourceFile = Get-Item -LiteralPath $script:CacheFile
    $sourceHash = (Get-FileHash -LiteralPath $script:CacheFile -Algorithm SHA256).Hash
    $manifest = [pscustomobject]@{
        SchemaVersion = 1
        CatalogMode = 'source-csv-with-in-memory-index'
        RecordsPersisted = $false
        SourceName = 'ÖKOBAUDAT'
        LicenseStatus = $script:CatalogLicenseStatus
        UsageNotice = $script:CatalogUsageNotice
        Release = if ($script:SourceMetadata) { $script:SourceMetadata.Release } else { $null }
        DataStockId = if ($script:SourceMetadata) { $script:SourceMetadata.DataStockId } else { $null }
        ReleasePageUrl = $script:ReleasePageUrl
        DownloadUrl = if ($script:SourceMetadata) { $script:SourceMetadata.DownloadUrl } else { $null }
        DownloadedAtUtc = if ($script:SourceMetadata) { $script:SourceMetadata.DownloadedAtUtc } else { $null }
        SourceFileName = $sourceFile.Name
        SourceFileBytes = $sourceFile.Length
        SourceFileSha256 = $sourceHash
        RecordCount = $RecordCount
        CacheStatus = $script:CacheStatus
        Warning = $script:DataWarning
        BuiltAtUtc = [DateTime]::UtcNow.ToString('o')
    }

    $manifestPath = Join-Path $catalogDirectory 'manifest.json'
    Write-OekoCacheMetadata -Path $manifestPath -Metadata $manifest
    $script:CatalogManifest = $manifest
    $script:CatalogStatus = 'ready'
}

function Get-SourceProvenance {
    Ensure-UserImportState
    $metadata = $script:SourceMetadata
    $catalogManifest = $script:CatalogManifest
    return [pscustomobject]@{
        sourceName = 'ÖKOBAUDAT'
        release = if ($metadata) { $metadata.Release } else { $null }
        dataStockId = if ($metadata) { $metadata.DataStockId } else { $null }
        releasePageUrl = $script:ReleasePageUrl
        downloadUrl = if ($metadata) { $metadata.DownloadUrl } else { $null }
        downloadedAtUtc = if ($metadata) { $metadata.DownloadedAtUtc } else { $null }
        retrievedAt = $script:RetrievedAt
        cacheStatus = $script:CacheStatus
        warning = $script:DataWarning
        standard = 'EN 15804+A2'
        modules = 'A1-A3'
        catalogStatus = $script:CatalogStatus
        catalogMode = 'source-csv-with-in-memory-index'
        catalogRecordCount = if ($null -ne $script:Dataset) { $script:Dataset.Length } elseif ($catalogManifest) { $catalogManifest.RecordCount } else { $null }
        catalogManifest = 'local-app-data/catalog/manifest.json'
        licenseStatus = $script:CatalogLicenseStatus
        usageNotice = $script:CatalogUsageNotice
        userImportRecordCount = @($script:UserImportRecords).Count
        userImportBatchCount = @($script:UserImportBatches).Count
        userImportLicenseStatus = $script:UserImportLicenseStatus
        userImportUsageNotice = $script:UserImportUsageNotice
    }
}

function Convert-ToNumber {
    param([string]$Value)

    $number = 0.0
    $style = [System.Globalization.NumberStyles]::Float
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if ([double]::TryParse($Value, $style, $culture, [ref]$number)) {
        return $number
    }

    return $null
}

function Get-ValidityStatus {
    param([string]$ValidUntil)

    $year = 0
    if (-not [int]::TryParse($ValidUntil, [ref]$year)) {
        return 'unknown'
    }

    if ($year -lt [DateTime]::UtcNow.Year) {
        return 'expired'
    }

    return 'valid'
}

function Get-MaterialFamilyName {
    param([string]$Name)

    $familyName = $Name -replace '(?i),?\s*Rezept\s+Nummer\b.*$', ''
    return $familyName.Trim().TrimEnd(',', ';')
}

function Get-ComparisonClass {
    param(
        [string]$Name,
        [string]$Category
    )

    $familyName = Get-MaterialFamilyName -Name $Name
    if ($Category -match 'Mörtel und Beton / Beton') {
        return ($familyName -replace '(?i)\s+ECOPactR?\s*$', '').Trim()
    }

    return $familyName
}

function Get-SearchPeerStatus {
    param([object]$Record)

    if ($Record.Validity -eq 'valid' -and
        $null -ne $Record.RatingRank -and
        $Record.RatingCount -ge 3) {
        return 'ranked'
    }

    if ($Record.Validity -eq 'expired') {
        return 'expired'
    }
    if ($Record.Validity -ne 'valid') {
        return 'validity-unknown'
    }

    if ($null -ne $Record.Gwp -and
        -not [string]::IsNullOrWhiteSpace($Record.Category) -and
        -not [string]::IsNullOrWhiteSpace($Record.ComparisonClass) -and
        -not [string]::IsNullOrWhiteSpace($Record.Unit) -and
        -not [string]::IsNullOrWhiteSpace($Record.ReferenceAmount)) {
        return 'unclassified'
    }

    return 'incomplete'
}

function Get-MaterialAlternativeAssessment {
    param(
        [object]$Record,
        [string]$Application
    )

    if ([string]::IsNullOrWhiteSpace($Application)) {
        return [pscustomobject]@{
            Status = 'needs_application'
            Application = ''
            Candidate = ''
            Reason = 'Ein möglicher Materialersatz hängt vom konkreten Bauteil ab. Wähle zuerst den Einsatz; ohne diese Angabe wird kein Ersatzmaterial vorgeschlagen.'
            Checks = @()
        }
    }

    $checks = switch -Exact ($Application) {
        'Außenwand / Fassade' {
            @(
                'Gleiche Wandfunktion und Bezugsgröße, zum Beispiel ein gleichwertiger Wandaufbau statt nur 1 m³ Rohmaterial.',
                'Tragfähigkeit, Wanddicke, Brand-, Schall- und Wärmeschutz sowie Feuchte- und Einbauanforderungen.',
                'Gleiche Lebenszyklusmodule und dokumentierte Quelle für beide vollständigen Bauteilaufbauten.'
            )
        }
        'Mauerwerk' {
            @(
                'Gleiche tragende oder nicht tragende Funktion und vergleichbare Wandgeometrie.',
                'Tragfähigkeit, Wanddicke, Brand-, Schall- und Wärmeschutz sowie Feuchte- und Einbauanforderungen.',
                'Vergleich je funktional gleichwertigem Wandaufbau mit gleicher Bezugsgrenze und Lebenszyklusphase.'
            )
        }
        'Dämmung' {
            @(
                'Gleiche Dämmwirkung des vollständigen Aufbaus (zum Beispiel vergleichbarer Wärmedurchgangswiderstand).',
                'Einbaudicke, Feuchteverhalten, Brandschutz, Nutzungsdauer und erforderliche Zusatzschichten.',
                'Vergleich je funktional gleichwertiger Fläche und mit identischen Lebenszyklusmodulen.'
            )
        }
        'Dach' {
            @(
                'Gleiche Dachfunktion und vollständiger Aufbau einschließlich erforderlicher Zusatzschichten.',
                'Tragfähigkeit, Brand-, Wärme- und Feuchteschutz sowie Nutzungsdauer.',
                'Vergleich je gleichwertiger Dachfläche und mit identischen Lebenszyklusmodulen.'
            )
        }
        'Boden / Decke' {
            @(
                'Gleiche Boden- oder Deckenkonstruktion und funktionale Bezugsgröße.',
                'Tragfähigkeit, Brand-, Schall- und Wärmeschutz sowie Aufbauhöhe.',
                'Vergleich des vollständigen Aufbaus mit identischer Bezugsgrenze und Lebenszyklusphase.'
            )
        }
        'Tragwerk' {
            @(
                'Gleiche Tragfunktion und nachgewiesene Bemessungsleistung.',
                'Spannweite, Lasten, Brandschutz, Verbindungen und erforderliche Zusatzbauteile.',
                'Vergleich je gleichwertiger Tragwerksleistung und mit identischen Lebenszyklusmodulen.'
            )
        }
        'Innenausbau' {
            @(
                'Gleiche Funktion des vollständigen Innenausbaus einschließlich Beschichtungen und Befestigungen.',
                'Brandschutz, Schall- und Feuchteschutz, Nutzungsdauer und erforderliche Zusatzschichten.',
                'Vergleich je gleichwertiger Fläche und mit identischen Lebenszyklusmodulen.'
            )
        }
        default {
            @(
                'Gleiche technische Funktion und nachgewiesene Leistung des Bauteils.',
                'Gleiche funktionale Bezugsgröße, Bezugsgrenze, Lebenszyklusmodule und Nutzungsdauer.'
            )
        }
    }

    $candidate = ''
    $status = 'not_assessed'
    $reason = 'Der aktuelle Prototyp prüft keine materialübergreifende funktionale Gleichwertigkeit. Ein niedrigerer GWP-Rohwert je Materialmenge belegt weder einen besseren Bauteilaufbau noch eine Austauschbarkeit.'
    if (($Application -eq 'Außenwand / Fassade' -or $Application -eq 'Mauerwerk') -and
        ($Record.Category -match 'Mörtel und Beton / Beton' -or $Record.Name -match '(?i)\bBeton\b')) {
        $candidate = 'Kalksandstein-Mauerwerk'
        $status = 'conditional_candidate'
        $reason = 'Bedingter Prüfpfad, keine Empfehlung: Kalksandstein-Mauerwerk kommt nur für eine geeignete Wand- oder Mauerwerksanwendung infrage. Die vorliegenden Rohmaterial-Datensätze belegen keinen gleichwertigen Wandaufbau und keinen ökologischen Vorteil; deshalb werden keine Materialwerte gegeneinander gestellt.'
    }

    return [pscustomobject]@{
        Status = $status
        Application = $Application
        Candidate = $candidate
        Reason = $reason
        Checks = @($checks)
    }
}

function Get-CategoryGroupName {
    param([string]$Category)

    $parts = @($Category -split ' / ' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($parts.Length -gt 1) {
        return "$($parts[0]) / $($parts[1])"
    }

    return [string]$Category
}

function Get-UserImportKey {
    param([object]$Record)
    return ('{0}|{1}|{2}' -f [string]$Record.SourceName, [string]$Record.SourceRecordId, [string]$Record.Version).ToLowerInvariant()
}

function Get-UserImportFingerprint {
    param([object]$Record)

    $values = @(
        [string]$Record.SourceName, [string]$Record.SourceRecordId, [string]$Record.Version,
        [string]$Record.ProductName, [string]$Record.Category, [string]$Record.Unit,
        [string]$Record.ReferenceAmount, [string]$Record.Gwp, [string]$Record.Standard,
        [string]$Record.Modules, [string]$Record.ValidUntil, [string]$Record.SourceUrl,
        [string]$Record.LicenseNotice, [string]$Record.SolarReflectance.Value,
        [string]$Record.SolarReflectance.Method, [string]$Record.SolarReflectance.Wavelength
    )
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($values -join "`n"))
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $hash.Dispose()
    }
}

function Ensure-UserImportState {
    if ($script:UserImportStateLoaded) {
        return
    }

    $script:UserImportBatches = @()
    $script:UserImportRecords = @()
    if (Test-Path -LiteralPath $script:UserImportStoreFile) {
        if ((Get-Item -LiteralPath $script:UserImportStoreFile).Length -gt $script:UserImportMaxStoreBytes) {
            throw 'Der lokale Import-Speicher überschreitet das zulässige Größenlimit.'
        }
        $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $storeText = [System.IO.File]::ReadAllText($script:UserImportStoreFile, $strictUtf8)
        $store = ConvertFrom-Json -InputObject $storeText -ErrorAction Stop
        if ($store.SchemaVersion -ne 1 -or $null -eq $store.Batches) {
            throw 'Der lokale Benutzerimport-Speicher hat ein unbekanntes Format.'
        }
        $script:UserImportBatches = @($store.Batches)
        foreach ($batch in $script:UserImportBatches) {
            foreach ($record in @($batch.Records)) {
                $script:UserImportRecords += $record
            }
        }
        if (@($script:UserImportRecords).Count -gt $script:UserImportMaxStoredRecords) {
            throw 'Der lokale Import-Speicher überschreitet das zulässige Datensatzlimit.'
        }
    }

    $script:UserImportStateLoaded = $true
}

function Save-UserImportState {
    param([object[]]$Batches)

    if (-not (Test-Path -LiteralPath $script:CacheDirectory)) {
        New-Item -ItemType Directory -Path $script:CacheDirectory -Force | Out-Null
    }
    $store = [pscustomobject]@{
        SchemaVersion = 1
        Batches = @($Batches)
    }
    $json = ConvertTo-Json -InputObject $store -Depth 20
    $encoding = [System.Text.UTF8Encoding]::new($false)
    $bytes = $encoding.GetBytes($json)
    if ($bytes.Length -gt $script:UserImportMaxStoreBytes) {
        throw 'Der lokale Import-Speicher hat sein Größenlimit erreicht. Entferne zuerst einen Import.'
    }

    $temporaryFile = Join-Path $script:CacheDirectory ("user-imports.{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllBytes($temporaryFile, $bytes)
        Move-FileAtomically -Source $temporaryFile -Destination $script:UserImportStoreFile
    }
    finally {
        if (Test-Path -LiteralPath $temporaryFile) {
            Remove-Item -LiteralPath $temporaryFile -Force
        }
    }

    $script:UserImportBatches = @($Batches)
    $script:UserImportRecords = @()
    foreach ($batch in $script:UserImportBatches) {
        foreach ($record in @($batch.Records)) {
            $script:UserImportRecords += $record
        }
    }
    $script:UserImportStateLoaded = $true
    $script:CombinedCatalogIndex = $null
}

function ConvertFrom-UserCatalogCsv {
    param([Parameter(Mandatory)][string]$Text)

    $expectedHeaders = @(
        'SourceName', 'SourceRecordId', 'Version', 'ProductName', 'Category',
        'Unit', 'ReferenceAmount', 'GwpKgCO2e', 'Standard', 'Modules',
        'ValidUntil', 'SourceUrl', 'LicenseNotice', 'SolarReflectancePercent',
        'SolarReflectanceMethod', 'SolarReflectanceWavelength'
    )
    $reader = [System.IO.StringReader]::new($Text)
    $parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($reader)
    $records = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[object]]::new()
    $dataRowCount = 0
    try {
        $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
        $parser.SetDelimiters(',')
        $parser.HasFieldsEnclosedInQuotes = $true
        $parser.TrimWhiteSpace = $false
        if ($parser.EndOfData) {
            throw 'Die CSV-Datei ist leer.'
        }
        $headers = @($parser.ReadFields())
        if ($headers.Length -gt 0) {
            $headers[0] = $headers[0].TrimStart([char]0xFEFF)
        }
        $headers = @($headers | ForEach-Object { ([string]$_).Trim() })
        if (($headers -join '|') -cne ($expectedHeaders -join '|')) {
            throw ("Die CSV-Kopfzeile muss exakt lauten: {0}" -f ($expectedHeaders -join ','))
        }

        $rowNumber = 1
        while (-not $parser.EndOfData) {
            $rowNumber++
            $dataRowCount++
            $fields = @($parser.ReadFields())
            if ($fields.Length -ne $expectedHeaders.Length) {
                $errors.Add([pscustomobject]@{ row = $rowNumber; field = ''; message = 'Die Zeile hat eine andere Spaltenzahl als die Kopfzeile.' })
                continue
            }
            $values = @{}
            for ($index = 0; $index -lt $expectedHeaders.Length; $index++) {
                $values[$expectedHeaders[$index]] = ([string]$fields[$index]).Trim()
                if ($values[$expectedHeaders[$index]].Length -gt 256) {
                    $errors.Add([pscustomobject]@{
                        row = $rowNumber
                        field = $expectedHeaders[$index]
                        message = 'CSV-Felder dürfen höchstens 256 Zeichen enthalten.'
                    })
                }
            }
            if (@($errors | Where-Object { $_.row -eq $rowNumber }).Count -gt 0) {
                continue
            }

            $rowIssues = [System.Collections.Generic.List[object]]::new()
            foreach ($fieldName in @('SourceName', 'SourceRecordId', 'Version', 'ProductName', 'Category', 'SourceUrl', 'LicenseNotice')) {
                if ([string]::IsNullOrWhiteSpace($values[$fieldName])) {
                    $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = $fieldName; message = 'Pflichtfeld darf nicht leer sein.' })
                }
                elseif ($values[$fieldName].Length -gt 256) {
                    $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = $fieldName; message = 'Textfeld darf höchstens 256 Zeichen enthalten.' })
                }
                elseif ($values[$fieldName] -match '^[=+@]') {
                    $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = $fieldName; message = 'Tabellenformelartige Texteingabe ist nicht zulässig.' })
                }
            }

            $sourceUri = $null
            if (-not [string]::IsNullOrWhiteSpace($values.SourceUrl) -and
                (-not [uri]::TryCreate($values.SourceUrl, [System.UriKind]::Absolute, [ref]$sourceUri) -or $sourceUri.Scheme -ne 'https')) {
                $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = 'SourceUrl'; message = 'Die Quelle muss eine absolute HTTPS-Adresse sein.' })
            }

            $gwp = $null
            $hasGwpData = @('Unit', 'ReferenceAmount', 'GwpKgCO2e', 'Standard', 'Modules', 'ValidUntil') |
                Where-Object { -not [string]::IsNullOrWhiteSpace($values[$_]) }
            $gwpComplete = $hasGwpData.Count -eq 6
            if ($hasGwpData.Count -gt 0 -and -not $gwpComplete) {
                $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = 'GwpKgCO2e'; message = 'GWP-Felder müssen vollständig ausgefüllt werden.' })
            }
            if ($gwpComplete) {
                $number = 0.0
                if (-not [double]::TryParse($values.GwpKgCO2e, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or [double]::IsNaN($number) -or [double]::IsInfinity($number)) {
                    $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = 'GwpKgCO2e'; message = 'GWP muss eine endliche Zahl in kg CO2e sein.' })
                }
                else {
                    $gwp = $number
                }
                $referenceAmount = 0.0
                if (-not [double]::TryParse($values.ReferenceAmount, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$referenceAmount) -or $referenceAmount -le 0 -or [double]::IsNaN($referenceAmount) -or [double]::IsInfinity($referenceAmount)) {
                    $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = 'ReferenceAmount'; message = 'Bezugsmenge muss eine endliche Zahl größer als null sein.' })
                }
                if (@('m', 'cm', 'mm', 'm2', 'cm2', 'mm2', 'm3', 'l', 'kg', 'g', 't', 'st', 'stk') -notcontains $values.Unit.ToLowerInvariant()) {
                    $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = 'Unit'; message = 'Einheit wird nicht unterstützt; zulässig sind m, cm, mm, m2, cm2, mm2, m3, l, kg, g, t und st.' })
                }
                if ($values.Standard -cne 'EN 15804+A2' -or $values.Modules -cne 'A1-A3') {
                    $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = 'Standard'; message = 'Für GWP-Berechnungen werden ausschließlich EN 15804+A2 und Module A1-A3 akzeptiert.' })
                }
                if ($values.ValidUntil -notmatch '^\d{4}$' -or [int]$values.ValidUntil -lt 1900) {
                    $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = 'ValidUntil'; message = 'Gültig-bis muss ein vierstelliges Jahr sein.' })
                }
            }

            $solar = $null
            $solarFields = @('SolarReflectancePercent', 'SolarReflectanceMethod', 'SolarReflectanceWavelength')
            $hasSolarData = @($solarFields | Where-Object { -not [string]::IsNullOrWhiteSpace($values[$_]) })
            if ($hasSolarData.Count -gt 0 -and $hasSolarData.Count -ne $solarFields.Count) {
                $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = 'SolarReflectancePercent'; message = 'Solarreflexion benötigt Wert, Messmethode und Wellenlängenbereich.' })
            }
            elseif ($hasSolarData.Count -eq $solarFields.Count) {
                $reflectance = 0.0
                if (-not [double]::TryParse($values.SolarReflectancePercent, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$reflectance) -or $reflectance -lt 0 -or $reflectance -gt 100 -or [double]::IsNaN($reflectance) -or [double]::IsInfinity($reflectance)) {
                    $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = 'SolarReflectancePercent'; message = 'Solarreflexion muss ein Zahlenwert zwischen 0 und 100 Prozent sein.' })
                }
                else {
                    $solar = [pscustomobject]@{
                        Value = $reflectance
                        Unit = '%'
                        Method = $values.SolarReflectanceMethod
                        Wavelength = $values.SolarReflectanceWavelength
                        SourceName = $values.SourceName
                        SourceUrl = $values.SourceUrl
                    }
                }
            }
            if (-not $gwpComplete -and $null -eq $solar) {
                $rowIssues.Add([pscustomobject]@{ row = $rowNumber; field = 'GwpKgCO2e'; message = 'Mindestens vollständige GWP-Daten oder vollständige Solarreflexionsdaten angeben.' })
            }
            foreach ($issue in $rowIssues) {
                $errors.Add($issue)
            }
            if ($rowIssues.Count -gt 0) {
                continue
            }

            $validUntil = if ($gwpComplete) { $values.ValidUntil } else { '' }
            $validity = if (-not $gwpComplete) { 'unknown' } elseif ([int]$validUntil -lt [DateTime]::UtcNow.Year) { 'expired' } else { 'valid' }
            $records.Add([pscustomobject]@{
                Row = $rowNumber
                SourceName = $values.SourceName
                SourceRecordId = $values.SourceRecordId
                Version = $values.Version
                ProductName = $values.ProductName
                Category = $values.Category
                Unit = if ($gwpComplete) { $values.Unit } else { '' }
                ReferenceAmount = if ($gwpComplete) { $values.ReferenceAmount } else { '' }
                Gwp = $gwp
                Standard = if ($gwpComplete) { $values.Standard } else { '' }
                Modules = if ($gwpComplete) { $values.Modules } else { '' }
                ValidUntil = $validUntil
                Validity = $validity
                SourceUrl = $values.SourceUrl
                LicenseNotice = $values.LicenseNotice
                SolarReflectance = $solar
            })
        }
    }
    finally {
        $parser.Dispose()
        $reader.Dispose()
    }

    if ($dataRowCount -gt $script:UserImportMaxRows) {
        throw "Die CSV-Datei überschreitet das Limit von $($script:UserImportMaxRows) Datenzeilen."
    }
    return [pscustomobject]@{ Records = $records.ToArray(); Errors = $errors.ToArray(); RowCount = $dataRowCount }
}

function ConvertTo-UserImportRecord {
    param(
        [object]$Record,
        [string]$BatchId,
        [int]$RecordNumber,
        [string]$ImportedAt
    )

    return [pscustomobject]@{
        Id = "USER-$BatchId-$RecordNumber"
        Version = $Record.Version
        Name = $Record.ProductName
        FamilyName = $Record.ProductName
        ComparisonClass = $Record.ProductName
        Category = $Record.Category
        CategoryGroup = Get-CategoryGroupName -Category $Record.Category
        Unit = $Record.Unit
        ReferenceAmount = $Record.ReferenceAmount
        Gwp = $Record.Gwp
        Owner = $Record.SourceName
        ReferenceYear = $null
        ValidUntil = $Record.ValidUntil
        Validity = $Record.Validity
        RatingGroup = 'nicht bewertet'
        RatingRank = $null
        RatingCount = 0
        Registration = $Record.SourceRecordId
        Url = $Record.SourceUrl
        SourceName = $Record.SourceName
        SourceUrl = $Record.SourceUrl
        RecordKind = 'user-import'
        SourceRecordId = $Record.SourceRecordId
        GwpStandard = $Record.Standard
        GwpModules = $Record.Modules
        LicenseStatus = $script:UserImportLicenseStatus
        LicenseNotice = $Record.LicenseNotice
        SolarReflectance = $Record.SolarReflectance
        UserImportBatchId = $BatchId
        DataStockId = $Record.SourceRecordId
        DataStockVersion = $Record.Version
        RetrievedAt = $ImportedAt
        CacheStatus = 'local-user-import'
        Metrics = @()
        SourceNameKey = $Record.SourceName
        ProductName = $Record.ProductName
        Standard = $Record.Standard
        Modules = $Record.Modules
        ValidUntilYear = $Record.ValidUntil
        LicenseNoticeOriginal = $Record.LicenseNotice
    }
}

function New-UserImportPreview {
    param([Parameter(Mandatory)][string]$CsvText)

    Ensure-UserImportState
    foreach ($pendingId in @($script:PendingUserImports.Keys)) {
        if ([DateTime]::UtcNow - $script:PendingUserImports[$pendingId].CreatedAt -gt [TimeSpan]::FromMinutes(30)) {
            $script:PendingUserImports.Remove($pendingId)
        }
    }
    if ($script:PendingUserImports.Count -ge 10) {
        throw 'Es sind bereits zehn Importvorschauen offen. Bitte bestätige oder verwerfe eine Vorschau.'
    }
    $parsed = ConvertFrom-UserCatalogCsv -Text $CsvText
    $errors = [System.Collections.Generic.List[object]]::new()
    foreach ($errorItem in @($parsed.Errors)) {
        $errors.Add($errorItem)
    }
    $accepted = [System.Collections.Generic.List[object]]::new()
    $duplicateRows = 0
    $existingByKey = @{}
    foreach ($existing in @($script:UserImportRecords)) {
        $key = Get-UserImportKey -Record $existing
        if (-not $existingByKey.ContainsKey($key)) {
            $existingByKey[$key] = [System.Collections.Generic.List[string]]::new()
        }
        $existingByKey[$key].Add((Get-UserImportFingerprint -Record $existing))
    }

    foreach ($group in @($parsed.Records | Group-Object -Property { Get-UserImportKey -Record $_ })) {
        $items = @($group.Group)
        $fingerprints = @($items | ForEach-Object { Get-UserImportFingerprint -Record $_ } | Select-Object -Unique)
        if ($existingByKey.ContainsKey($group.Name)) {
            foreach ($item in $items) {
                if ($existingByKey[$group.Name].Contains((Get-UserImportFingerprint -Record $item))) {
                    $duplicateRows++
                }
                else {
                    $errors.Add([pscustomobject]@{
                        row = $item.Row
                        field = 'SourceRecordId'
                        message = 'Diese Quellen-ID und Version existiert bereits mit abweichenden Inhalten. Der Konflikt wurde nicht importiert.'
                    })
                }
            }
            continue
        }
        if ($fingerprints.Count -gt 1) {
            foreach ($item in $items) {
                $errors.Add([pscustomobject]@{
                    row = $item.Row
                    field = 'SourceRecordId'
                    message = 'Dieselbe Quellen-ID und Version kommt in der Datei mit unterschiedlichen Inhalten vor.'
                })
            }
            continue
        }
        $accepted.Add($items[0])
        $duplicateRows += [Math]::Max(0, $items.Count - 1)
    }

    $previewId = [guid]::NewGuid().ToString('N')
    $script:PendingUserImports[$previewId] = @{
        CreatedAt = [DateTime]::UtcNow
        Records = $accepted.ToArray()
    }
    $errorRows = @($errors | Select-Object -ExpandProperty row -Unique).Count
    return [pscustomobject]@{
        previewId = $previewId
        rowCount = $parsed.RowCount
        validRowCount = $accepted.Count
        duplicateRowCount = $duplicateRows
        errorRowCount = $errorRows
        errors = @($errors | Select-Object -First 100)
        samples = @($accepted | Select-Object -First 8 | ForEach-Object {
            [pscustomobject]@{
                productName = $_.ProductName
                sourceName = $_.SourceName
                sourceRecordId = $_.SourceRecordId
                gwpAvailable = ($null -ne $_.Gwp)
                solarReflectanceAvailable = ($null -ne $_.SolarReflectance)
            }
        })
    }
}

function Confirm-UserImport {
    param(
        [Parameter(Mandatory)][string]$PreviewId,
        [bool]$RightsConfirmed
    )

    if (-not $RightsConfirmed) {
        throw 'Bitte bestätige, dass du diese Daten rechtmäßig lokal speichern und verwenden darfst.'
    }
    if (-not $script:PendingUserImports.ContainsKey($PreviewId)) {
        throw 'Die Importvorschau ist abgelaufen. Bitte lade die CSV-Datei erneut hoch.'
    }
    $preview = $script:PendingUserImports[$PreviewId]
    if ([DateTime]::UtcNow - $preview.CreatedAt -gt [TimeSpan]::FromMinutes(30)) {
        $script:PendingUserImports.Remove($PreviewId)
        throw 'Die Importvorschau ist abgelaufen. Bitte lade die CSV-Datei erneut hoch.'
    }
    Ensure-UserImportState
    $currentKeys = @{}
    foreach ($record in @($script:UserImportRecords)) {
        $key = Get-UserImportKey -Record $record
        if (-not $currentKeys.ContainsKey($key)) {
            $currentKeys[$key] = [System.Collections.Generic.List[string]]::new()
        }
        $currentKeys[$key].Add((Get-UserImportFingerprint -Record $record))
    }

    $batchId = [guid]::NewGuid().ToString('N')
    $importedAt = [DateTime]::UtcNow.ToString('o')
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($preview.Records)) {
        $key = Get-UserImportKey -Record $record
        $fingerprint = Get-UserImportFingerprint -Record $record
        if ($currentKeys.ContainsKey($key)) {
            if ($currentKeys[$key].Contains($fingerprint)) {
                continue
            }
            throw 'Der Importkonflikt hat sich seit der Vorschau geändert. Bitte erstelle eine neue Vorschau.'
        }
        $records.Add((ConvertTo-UserImportRecord -Record $record -BatchId $batchId -RecordNumber ($records.Count + 1) -ImportedAt $importedAt))
        $currentKeys[$key] = [System.Collections.Generic.List[string]]::new()
        $currentKeys[$key].Add($fingerprint)
    }
    if ($records.Count -eq 0) {
        throw 'Es gibt keine neuen, gültigen Datensätze zu importieren.'
    }
    if (@($script:UserImportRecords).Count + $records.Count -gt $script:UserImportMaxStoredRecords) {
        throw "Der lokale Import-Speicher ist auf $($script:UserImportMaxStoredRecords) Datensätze begrenzt."
    }
    $batch = [pscustomobject]@{
        Id = $batchId
        ImportedAt = $importedAt
        RightsConfirmedAt = $importedAt
        SourceNames = @($records | Select-Object -ExpandProperty SourceName -Unique)
        RecordCount = $records.Count
        Records = $records.ToArray()
    }
    $nextBatches = @($script:UserImportBatches) + @($batch)
    Save-UserImportState -Batches $nextBatches
    $script:PendingUserImports.Remove($PreviewId)
    return [pscustomobject]@{
        batchId = $batchId
        importedRecordCount = $records.Count
        importedAt = $importedAt
        sourceNames = $batch.SourceNames
    }
}

function Remove-UserImportBatch {
    param([Parameter(Mandatory)][string]$BatchId)

    Ensure-UserImportState
    $remaining = @($script:UserImportBatches | Where-Object { $_.Id -ne $BatchId })
    if ($remaining.Count -eq @($script:UserImportBatches).Count) {
        return $false
    }
    Save-UserImportState -Batches $remaining
    return $true
}

function Get-UserImportBatchSummary {
    Ensure-UserImportState
    return @($script:UserImportBatches | ForEach-Object {
        [pscustomobject]@{
            id = $_.Id
            importedAt = $_.ImportedAt
            sourceNames = @($_.SourceNames)
            recordCount = [int]$_.RecordCount
            licenseStatus = $script:UserImportLicenseStatus
        }
    })
}

function Remove-PendingUserImport {
    param([Parameter(Mandatory)][string]$PreviewId)
    if (-not $script:PendingUserImports.ContainsKey($PreviewId)) {
        return $false
    }
    $script:PendingUserImports.Remove($PreviewId)
    return $true
}

function Ensure-Dataset {
    if ($null -ne $script:Dataset -and $null -ne $script:CatalogIndex) {
        return
    }

    if (-not (Test-Path -LiteralPath $script:CacheDirectory)) {
        New-Item -ItemType Directory -Path $script:CacheDirectory -Force | Out-Null
    }

    $cacheExists = Test-Path -LiteralPath $script:CacheFile
    $cacheMetadata = Read-OekoCacheMetadata -Path $script:CacheMetadataFile
    $officialExport = $null
    $releasePageError = $null
    try {
        $releasePage = Invoke-WebRequest -Uri $script:ReleasePageUrl -UseBasicParsing -TimeoutSec 15
        $officialExport = Get-OfficialExportInfo -Html $releasePage.Content
    }
    catch {
        $releasePageError = $_.Exception.Message
    }

    $cacheIsFresh = $false
    if ($cacheExists) {
        $cacheIsFresh = (Get-Item -LiteralPath $script:CacheFile).LastWriteTimeUtc -gt [DateTime]::UtcNow.AddDays(-1)
    }
    $cacheMatchesRelease = $officialExport -and
        $cacheMetadata -and
        -not $cacheMetadata.MetadataError -and
        $cacheMetadata.DataStockId -eq $officialExport.DataStockId -and
        $cacheMetadata.DownloadUrl -eq $officialExport.DownloadUrl -and
        $cacheMetadata.Release -eq $officialExport.Release
    $needsRefresh = -not $cacheExists -or -not $cacheIsFresh -or -not $cacheMatchesRelease

    if ($officialExport -and $needsRefresh) {
        $downloadFile = "$($script:CacheFile).download"
        try {
            Write-Host ("Lade ÖKOBAUDAT {0} über den offiziell verlinkten CSV-Export ..." -f $officialExport.Release)
            Invoke-WebRequest -Uri $officialExport.DownloadUrl -OutFile $downloadFile -UseBasicParsing -TimeoutSec 60
            [void](Test-OekoCsvFile -Path $downloadFile)
            Move-FileAtomically -Source $downloadFile -Destination $script:CacheFile

            $cacheMetadata = [pscustomobject]@{
                SourceName = $officialExport.SourceName
                Release = $officialExport.Release
                DataStockId = $officialExport.DataStockId
                DownloadUrl = $officialExport.DownloadUrl
                ReleasePageUrl = $officialExport.ReleasePageUrl
                Format = $officialExport.Format
                Standard = $officialExport.Standard
                Modules = $officialExport.Modules
                DownloadedAtUtc = [DateTime]::UtcNow.ToString('o')
            }
            try {
                Write-OekoCacheMetadata -Path $script:CacheMetadataFile -Metadata $cacheMetadata
            }
            catch {
                $script:DataWarning = "Der aktuelle ÖKOBAUDAT-Export wurde geladen, aber seine Cache-Metadaten konnten nicht gespeichert werden: $($_.Exception.Message)"
            }
            $script:SourceMetadata = $cacheMetadata
            $script:CacheStatus = 'updated'
        }
        catch {
            if ($downloadFile -and (Test-Path -LiteralPath $downloadFile)) {
                Remove-Item -LiteralPath $downloadFile
            }
            if (-not $cacheExists) {
                throw "Der offiziell verlinkte ÖKOBAUDAT-Export ($($officialExport.Release)) konnte nicht geladen oder validiert werden: $($_.Exception.Message)"
            }

            $script:DataWarning = "Die Aktualisierung von ÖKOBAUDAT $($officialExport.Release) ist fehlgeschlagen: $($_.Exception.Message) Es werden zwischengespeicherte Daten verwendet."
            Write-Warning $script:DataWarning
            $script:SourceMetadata = if ($cacheMetadata -and -not $cacheMetadata.MetadataError) { $cacheMetadata } else { $null }
            $script:CacheStatus = 'refresh-failed'
        }
    }
    elseif ($officialExport) {
        $script:SourceMetadata = $cacheMetadata
        $script:CacheStatus = 'current-cache'
    }
    elseif ($cacheExists) {
        $script:SourceMetadata = if ($cacheMetadata -and -not $cacheMetadata.MetadataError) { $cacheMetadata } else { $null }
        $script:CacheStatus = 'release-unverified-cache'
        if ($script:SourceMetadata) {
            $script:DataWarning = "Der aktuelle ÖKOBAUDAT-Datenstand konnte nicht auf der offiziellen Downloadseite geprüft werden ($releasePageError). Es werden zwischengespeicherte Daten aus $($script:SourceMetadata.Release) verwendet."
        }
        else {
            $script:DataWarning = "Der aktuelle ÖKOBAUDAT-Datenstand konnte nicht auf der offiziellen Downloadseite geprüft werden ($releasePageError). Der verwendete Cache hat keine verifizierbaren Datenstands-Metadaten."
        }
        Write-Warning $script:DataWarning
    }
    else {
        throw "Die offizielle ÖKOBAUDAT-Downloadseite konnte nicht geprüft werden und es gibt keinen Cache: $releasePageError"
    }

    $script:RetrievedAt = (Get-Item -LiteralPath $script:CacheFile).LastWriteTimeUtc.ToString('yyyy-MM-dd')
    if ($script:SourceMetadata -and $script:SourceMetadata.Release) {
        $script:DataSource = "OEKOBAUDAT $($script:SourceMetadata.Release), CSV-Export, EN 15804+A2, Modul A1-A3"
    }
    elseif ($script:SourceMetadata) {
        $script:DataSource = 'OEKOBAUDAT-CSV-Export, Release nicht verfügbar, EN 15804+A2, Modul A1-A3'
    }
    else {
        $script:DataSource = 'OEKOBAUDAT-CSV-Export, Datenstand nicht verifiziert, EN 15804+A2, Modul A1-A3'
    }
    $encoding = [System.Text.Encoding]::GetEncoding(28591)
    $parser = [Microsoft.VisualBasic.FileIO.TextFieldParser]::new($script:CacheFile, $encoding)
    $parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
    $parser.SetDelimiters(';')
    $parser.HasFieldsEnclosedInQuotes = $true
    $parser.TrimWhiteSpace = $false

    $records = [System.Collections.Generic.List[object]]::new()
    try {
        $headers = $parser.ReadFields()
        $columns = @{}
        for ($i = 0; $i -lt $headers.Length; $i++) {
            $columns[$headers[$i]] = $i
        }

        $metricDefinitions = @(
            @{ Field = 'AP (A2)'; Label = 'Versauerung'; Unit = 'mol H+-Aequivalent' },
            @{ Field = 'EPfreshwater (A2)'; Label = 'Suesswasser-Eutrophierung'; Unit = 'kg P-Aequivalent' },
            @{ Field = 'EPmarine (A2)'; Label = 'Meeres-Eutrophierung'; Unit = 'kg N-Aequivalent' },
            @{ Field = 'EPterrestrial (A2)'; Label = 'Terrestrische Eutrophierung'; Unit = 'mol N-Aequivalent' },
            @{ Field = 'ODP (A2)'; Label = 'Ozonabbau'; Unit = 'kg CFC-11-Aequivalent' },
            @{ Field = 'POCP (A2)'; Label = 'Sommersmog'; Unit = 'kg NMVOC-Aequivalent' },
            @{ Field = 'ADPF (A2)'; Label = 'Fossiler Ressourcenverbrauch'; Unit = 'MJ' },
            @{ Field = 'ADPE (A2)'; Label = 'Mineralischer Ressourcenverbrauch'; Unit = 'kg Sb-Aequivalent' },
            @{ Field = 'WDP (A2)'; Label = 'Wasserknappheit'; Unit = 'm3 Welt-Aequivalent' }
        )

        while (-not $parser.EndOfData) {
            $fields = $parser.ReadFields()
            if ($null -eq $fields -or $fields.Length -lt $headers.Length) {
                continue
            }

            $compliance = Get-Field -Fields $fields -Columns $columns -Name 'Konformitaet'
            $module = Get-Field -Fields $fields -Columns $columns -Name 'Modul'
            if ($compliance -notmatch 'EN 15804\+A2' -or $module -ne 'A1-A3') {
                continue
            }

            $name = Get-Field -Fields $fields -Columns $columns -Name 'Name (de)'
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            $category = Get-Field -Fields $fields -Columns $columns -Name 'Kategorie (original)'
            $category = $category -replace "'\s*/\s*'", ' / ' -replace "'", ''
            $validUntil = Get-Field -Fields $fields -Columns $columns -Name 'Gueltig bis'
            $familyName = Get-MaterialFamilyName -Name $name
            $comparisonClass = Get-ComparisonClass -Name $name -Category $category
            $metrics = [System.Collections.Generic.List[object]]::new()
            foreach ($definition in $metricDefinitions) {
                $value = Convert-ToNumber (Get-Field -Fields $fields -Columns $columns -Name $definition.Field)
                if ($null -ne $value) {
                    $metrics.Add([pscustomobject]@{
                        Name = $definition.Label
                        Value = $value
                        Unit = $definition.Unit
                    })
                }
            }

            $records.Add([pscustomobject]@{
                Id = Get-Field -Fields $fields -Columns $columns -Name 'UUID'
                Version = Get-Field -Fields $fields -Columns $columns -Name 'Version'
                Name = $name
                FamilyName = $familyName
                ComparisonClass = $comparisonClass
                Category = $category
                CategoryGroup = Get-CategoryGroupName -Category $category
                Unit = Get-Field -Fields $fields -Columns $columns -Name 'Bezugseinheit'
                ReferenceAmount = Get-Field -Fields $fields -Columns $columns -Name 'Bezugsgroesse'
                Gwp = Convert-ToNumber (Get-Field -Fields $fields -Columns $columns -Name 'GWPtotal (A2)')
                Owner = Get-Field -Fields $fields -Columns $columns -Name 'Declaration owner'
                ReferenceYear = Get-Field -Fields $fields -Columns $columns -Name 'Referenzjahr'
                ValidUntil = $validUntil
                Validity = Get-ValidityStatus -ValidUntil $validUntil
                RatingGroup = 'nicht vergleichbar'
                RatingRank = $null
                RatingCount = 0
                Registration = Get-Field -Fields $fields -Columns $columns -Name 'Registrierungsnummer'
                Url = "https://www.oekobaudat.de/OEKOBAU.DAT/resource/processes/$(Get-Field -Fields $fields -Columns $columns -Name 'UUID')?version=$([uri]::EscapeDataString((Get-Field -Fields $fields -Columns $columns -Name 'Version')))"
                SourceName = 'ÖKOBAUDAT'
                SourceUrl = if ($script:SourceMetadata) { $script:SourceMetadata.ReleasePageUrl } else { $script:ReleasePageUrl }
                DataStockId = if ($script:SourceMetadata) { $script:SourceMetadata.DataStockId } else { $null }
                DataStockVersion = if ($script:SourceMetadata) { $script:SourceMetadata.Release } else { $null }
                RetrievedAt = $script:RetrievedAt
                CacheStatus = $script:CacheStatus
                Metrics = $metrics.ToArray()
            })
        }
    }
    finally {
        $parser.Close()
    }

    if ($records.Count -eq 0) {
        throw 'Im OEKOBAUDAT-Export wurden keine passenden Datensaetze fuer EN 15804+A2, Modul A1-A3 gefunden.'
    }

    $script:Dataset = $records.ToArray()
    $comparisonGroups = @($script:Dataset |
        Where-Object {
            $_.Validity -eq 'valid' -and
            $null -ne $_.Gwp -and
            -not [string]::IsNullOrWhiteSpace($_.Category) -and
            -not [string]::IsNullOrWhiteSpace($_.Unit) -and
            -not [string]::IsNullOrWhiteSpace($_.ReferenceAmount)
        } |
        Group-Object -Property { '{0}|{1}|{2}|{3}' -f $_.Category, $_.Unit, $_.ReferenceAmount, $_.ComparisonClass })

    foreach ($comparisonGroup in $comparisonGroups) {
        $ordered = @($comparisonGroup.Group | Sort-Object -Property Gwp, Name)
        $count = $ordered.Count
        if ($count -ge 3 -and $ordered[0].Gwp -eq $ordered[$count - 1].Gwp) {
            foreach ($record in $ordered) {
                $record.RatingGroup = 'nicht unterscheidbar'
                $record.RatingCount = $count
            }
            continue
        }

        $goodLimit = [Math]::Ceiling($count / 3.0)
        $middleLimit = [Math]::Ceiling((2 * $count) / 3.0)
        $goodThreshold = $ordered[$goodLimit - 1].Gwp
        $middleThreshold = $ordered[$middleLimit - 1].Gwp
        $previousValue = $null
        $rank = 0
        for ($index = 0; $index -lt $count; $index++) {
            $record = $ordered[$index]
            $record.RatingCount = $count
            if ($count -ge 3) {
                if ($null -eq $previousValue -or $record.Gwp -ne $previousValue) {
                    $rank = $index + 1
                }
                $record.RatingRank = $rank
                if ($record.Gwp -le $goodThreshold) {
                    $record.RatingGroup = 'gut'
                }
                elseif ($record.Gwp -le $middleThreshold) {
                    $record.RatingGroup = 'mittel'
                }
                else {
                    $record.RatingGroup = 'schlecht'
                }
                $previousValue = $record.Gwp
            }
        }
    }

    $script:CatalogIndex = Build-MaterialCatalogIndex -Records $script:Dataset
    try {
        Write-CatalogManifest -RecordCount $script:Dataset.Length
    }
    catch {
        $script:CatalogStatus = 'manifest-write-failed'
        $manifestWarning = "Der lokale Katalogindex ist im Arbeitsspeicher verfügbar, aber das Quellenmanifest konnte nicht gespeichert werden: $($_.Exception.Message)"
        $script:DataWarning = if ([string]::IsNullOrWhiteSpace($script:DataWarning)) { $manifestWarning } else { "$($script:DataWarning) $manifestWarning" }
        Write-Warning $manifestWarning
    }

    Write-Host ("OEKOBAUDAT-Katalog bereit: {0} Datensaetze; Quellenindex im Arbeitsspeicher." -f $script:Dataset.Length)
}

function Get-SearchableCatalog {
    Ensure-UserImportState
    if ($script:DataWarning -like 'ÖKOBAUDAT ist momentan nicht verfügbar; es werden nur lokale Benutzerimporte durchsucht.*') {
        $script:DataWarning = $null
    }
    try {
        Ensure-Dataset
    }
    catch {
        if (@($script:UserImportRecords).Count -eq 0) {
            throw
        }
        $script:DataWarning = "ÖKOBAUDAT ist momentan nicht verfügbar; es werden nur lokale Benutzerimporte durchsucht. $($_.Exception.Message)"
        $script:CatalogStatus = 'user-imports-only'
        $script:CacheStatus = 'unavailable'
    }

    $records = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $script:Dataset) {
        $records.AddRange([object[]]$script:Dataset)
    }
    if (@($script:UserImportRecords).Count -gt 0) {
        $records.AddRange([object[]]$script:UserImportRecords)
    }
    if ($records.Count -eq 0) {
        throw 'Es sind keine durchsuchbaren Katalogdatensätze verfügbar.'
    }
    if ($null -eq $script:CombinedCatalogIndex) {
        $script:CombinedCatalogIndex = Build-MaterialCatalogIndex -Records $records.ToArray()
    }
    return [pscustomobject]@{
        Records = $records.ToArray()
        Index = $script:CombinedCatalogIndex
    }
}

function Get-ItemView {
    param([object]$Record)

    $gwp = $null
    if ($null -ne $Record.Gwp) {
        $gwp = [double]$Record.Gwp
    }

    return [pscustomobject]@{
        Id = $Record.Id
        Version = $Record.Version
        Name = $Record.Name
        FamilyName = $Record.FamilyName
        ComparisonClass = $Record.ComparisonClass
        Category = $Record.Category
        CategoryGroup = $Record.CategoryGroup
        Unit = $Record.Unit
        ReferenceAmount = $Record.ReferenceAmount
        Gwp = $gwp
        Owner = $Record.Owner
        ReferenceYear = $Record.ReferenceYear
        ValidUntil = $Record.ValidUntil
        Validity = $Record.Validity
        Rating = [pscustomobject]@{
            Group = $Record.RatingGroup
            Rank = $Record.RatingRank
            Count = $Record.RatingCount
        }
        Registration = $Record.Registration
        Url = $Record.Url
        SourceName = $Record.SourceName
        SourceUrl = $Record.SourceUrl
        RecordKind = if ($Record.RecordKind) { $Record.RecordKind } else { 'source-catalog' }
        SourceRecordId = if ($Record.SourceRecordId) { $Record.SourceRecordId } else { $Record.Id }
        GwpStandard = if ($Record.GwpStandard) { $Record.GwpStandard } else { 'EN 15804+A2' }
        GwpModules = if ($Record.GwpModules) { $Record.GwpModules } else { 'A1-A3' }
        LicenseStatus = if ($Record.LicenseStatus) { $Record.LicenseStatus } else { $script:CatalogLicenseStatus }
        LicenseNotice = $Record.LicenseNotice
        SolarReflectance = $Record.SolarReflectance
        UserImportBatchId = $Record.UserImportBatchId
        DataStockId = $Record.DataStockId
        DataStockVersion = $Record.DataStockVersion
        RetrievedAt = $Record.RetrievedAt
        CacheStatus = $Record.CacheStatus
        Metrics = @($Record.Metrics)
    }
}

function Get-SearchItemView {
    param(
        [object]$Record,
        [string[]]$QueryTerms
    )

    $item = Get-ItemView -Record $Record
    $item.PSObject.Properties.Remove('Metrics')
    $item | Add-Member -NotePropertyName MatchedQueries -NotePropertyValue @(Get-RecordMatchedTerms -Record $Record -QueryTerms $QueryTerms)
    return $item
}

function Get-MetricComparisons {
    param(
        [object[]]$SelectedMetrics,
        [object[]]$AlternativeMetrics
    )

    $comparisons = [System.Collections.Generic.List[object]]::new()
    foreach ($selectedMetric in $SelectedMetrics) {
        $alternativeMetric = $AlternativeMetrics |
            Where-Object { $_.Name -eq $selectedMetric.Name -and $_.Unit -eq $selectedMetric.Unit } |
            Select-Object -First 1
        if ($null -eq $alternativeMetric) {
            continue
        }

        $relation = if ($alternativeMetric.Value -lt $selectedMetric.Value) {
            'lower'
        }
        elseif ($alternativeMetric.Value -gt $selectedMetric.Value) {
            'higher'
        }
        else {
            'equal'
        }
        $comparisons.Add([pscustomobject]@{
            Name = $selectedMetric.Name
            Unit = $selectedMetric.Unit
            SelectedValue = $selectedMetric.Value
            AlternativeValue = $alternativeMetric.Value
            Relation = $relation
        })
    }

    return $comparisons.ToArray()
}

function Handle-UserImportRequest {
    param([System.Net.HttpListenerContext]$Context)

    $path = $Context.Request.Url.AbsolutePath
    $method = $Context.Request.HttpMethod
    if ($path -eq '/api/import/list') {
        if ($method -ne 'GET') {
            Send-Json -Context $Context -StatusCode 405 -Value @{ error = 'Diese Importroute unterstützt nur GET.' }
            return
        }
        try {
            Send-Json -Context $Context -StatusCode 200 -Value @{
                batches = @(Get-UserImportBatchSummary)
                recordCount = @($script:UserImportRecords).Count
                licenseStatus = $script:UserImportLicenseStatus
                usageNotice = $script:UserImportUsageNotice
            }
        }
        catch {
            Send-Json -Context $Context -StatusCode 500 -Value @{ error = "Der lokale Import-Speicher konnte nicht gelesen werden: $($_.Exception.Message)" }
        }
        return
    }

    if ($path -notin @('/api/import/preview', '/api/import/confirm', '/api/import/remove', '/api/import/discard')) {
        Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Diese Importroute wurde nicht gefunden.' }
        return
    }
    if ($method -ne 'POST') {
        Send-Json -Context $Context -StatusCode 405 -Value @{ error = 'Diese Importroute unterstützt nur POST.' }
        return
    }

    try {
        Assert-SameOriginImportRequest -Context $Context
        if ($path -eq '/api/import/preview') {
            $contentType = ([string]$Context.Request.ContentType -split ';', 2)[0].Trim()
            $charset = [regex]::Match([string]$Context.Request.ContentType, '(?i)charset\s*=\s*"?([^;"\s]+)').Groups[1].Value
            if ($contentType -ine 'text/csv' -or ($charset -and $charset -ine 'utf-8')) {
                Send-Json -Context $Context -StatusCode 415 -Value @{ error = 'Bitte eine UTF-8-CSV-Datei hochladen.' }
                return
            }
            $csvText = Read-StrictUtf8RequestText -Request $Context.Request -MaximumBytes $script:UserImportMaxBytes
            $preview = New-UserImportPreview -CsvText $csvText
            Send-Json -Context $Context -StatusCode 200 -Value $preview
            return
        }

        $jsonType = ([string]$Context.Request.ContentType -split ';', 2)[0].Trim()
        if ($jsonType -ine 'application/json') {
            Send-Json -Context $Context -StatusCode 415 -Value @{ error = 'Die Anfrage muss application/json verwenden.' }
            return
        }
        $jsonText = Read-StrictUtf8RequestText -Request $Context.Request -MaximumBytes 16384
        $payload = ConvertFrom-Json -InputObject $jsonText -ErrorAction Stop
        if ($path -eq '/api/import/confirm') {
            if ([string]::IsNullOrWhiteSpace([string]$payload.previewId) -or $payload.previewId -notmatch '^[a-f0-9]{32}$') {
                Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Ungültige Importvorschau.' }
                return
            }
            $result = Confirm-UserImport -PreviewId $payload.previewId -RightsConfirmed ($payload.rightsConfirmed -eq $true)
            Send-Json -Context $Context -StatusCode 201 -Value $result
            return
        }

        if ($path -eq '/api/import/discard') {
            if ([string]::IsNullOrWhiteSpace([string]$payload.previewId) -or $payload.previewId -notmatch '^[a-f0-9]{32}$') {
                Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Ungültige Importvorschau.' }
                return
            }
            if (-not (Remove-PendingUserImport -PreviewId $payload.previewId)) {
                Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Diese Importvorschau wurde nicht gefunden.' }
                return
            }
            Send-Json -Context $Context -StatusCode 200 -Value @{ discarded = $true }
            return
        }

        if ([string]::IsNullOrWhiteSpace([string]$payload.batchId) -or $payload.batchId -notmatch '^[a-f0-9]{32}$') {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Ungültige Import-ID.' }
            return
        }
        if (-not (Remove-UserImportBatch -BatchId $payload.batchId)) {
            Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Dieser Import wurde nicht gefunden.' }
            return
        }
        Send-Json -Context $Context -StatusCode 200 -Value @{ removed = $true; batchId = $payload.batchId }
    }
    catch {
        $statusCode = if ($_.Exception.Data['StatusCode']) { [int]$_.Exception.Data['StatusCode'] } else { 400 }
        $errorMessage = [string]$_.Exception.Message
        if ($errorMessage -match 'abgelaufen') {
            $statusCode = 410
        }
        elseif ($errorMessage -match 'Konflikt') {
            $statusCode = 409
        }
        elseif ($errorMessage -match 'denselben App-Ursprung') {
            $statusCode = 403
        }
        Send-Json -Context $Context -StatusCode $statusCode -Value @{ error = $errorMessage }
    }
}

function Handle-Request {
    param([System.Net.HttpListenerContext]$Context)

    $path = $Context.Request.Url.AbsolutePath
    if ($path.StartsWith('/api/import/')) {
        Handle-UserImportRequest -Context $Context
        return
    }
    if ($path -eq '/api/health') {
        Send-Json -Context $Context -StatusCode 200 -Value @{
            ready = $true
            source = $script:DataSource
            datasetLoaded = ($null -ne $script:Dataset)
            provenance = (Get-SourceProvenance)
        }
        return
    }

    if ($path -eq '/api/search') {
        $query = [System.Web.HttpUtility]::ParseQueryString($Context.Request.Url.Query).Get('q')
        $query = ([string]$query).Trim()
        if ($query.Length -lt 2) {
            Send-Json -Context $Context -StatusCode 400 -Value @{ error = 'Bitte mindestens zwei Zeichen eingeben.' }
            return
        }

        $catalog = Get-SearchableCatalog
        $search = Find-MaterialRecords -Records $catalog.Records -Index $catalog.Index -Query $query
        $queryTerms = $search.QueryTerms
        $matchedTerms = $search.MatchedTerms
        $matches = $search.Records
        $families = [System.Collections.Generic.List[object]]::new()
        foreach ($family in @($matches | Group-Object -Property {
            if (-not [string]::IsNullOrWhiteSpace($_.ComparisonClass)) {
                return '{0}|{1}' -f $_.Category, $_.ComparisonClass
            }

            return '{0}|{1}|{2}' -f $_.Category, $_.FamilyName, $_.Id
        })) {
            $peerGroups = @($family.Group | Group-Object -Property {
                $status = Get-SearchPeerStatus -Record $_
                if ($status -eq 'incomplete') {
                    return '{0}|{1}' -f $status, $_.Id
                }

                return '{0}|{1}|{2}|{3}|{4}|{5}' -f $status, $_.Category, $_.ComparisonClass, $_.Unit, $_.ReferenceAmount, $_.Validity
            })
            $orderedPeerGroups = @($peerGroups | Sort-Object -Property @{
                Expression = {
                    switch (Get-SearchPeerStatus -Record $_.Group[0]) {
                        'ranked' { 0 }
                        'unclassified' { 1 }
                        'expired' { 2 }
                        'validity-unknown' { 3 }
                        default { 4 }
                    }
                }
            }, @{
                Expression = { $_.Group[0].ComparisonClass }
            }, @{
                Expression = { $_.Group[0].Unit }
            }, @{
                Expression = { $_.Group[0].ReferenceAmount }
            }, @{
                Expression = { $_.Group[0].Name }
            })
            $peerViews = [System.Collections.Generic.List[object]]::new()
            foreach ($peer in $orderedPeerGroups) {
                $peerRecords = @($peer.Group | Sort-Object -Property @{
                    Expression = { if ($null -ne $_.RatingRank) { [double]$_.RatingRank } else { [double]::MaxValue } }
                }, Name, Version, Id)
                $firstItem = $peerRecords[0]
                $peerViews.Add([pscustomobject]@{
                    Status = Get-SearchPeerStatus -Record $firstItem
                    ComparisonClass = $firstItem.ComparisonClass
                    Unit = $firstItem.Unit
                    ReferenceAmount = $firstItem.ReferenceAmount
                    RatingGroup = $firstItem.RatingGroup
                    Count = $peerRecords.Count
                    Items = @($peerRecords | Select-Object -First 5 | ForEach-Object { Get-SearchItemView -Record $_ -QueryTerms $queryTerms })
                })
            }

            $firstItem = $family.Group[0]
            $familyName = if ([string]::IsNullOrWhiteSpace($firstItem.ComparisonClass)) { $firstItem.FamilyName } else { $firstItem.ComparisonClass }
            $families.Add([pscustomobject]@{
                Name = $familyName
                Category = $firstItem.Category
                CategoryGroup = $firstItem.CategoryGroup
                Count = $family.Group.Count
                PeerGroups = $peerViews.ToArray()
            })
        }
        $orderedFamilies = @($families |
            Sort-Object -Property @{
                Expression = { Get-SearchTermPriority -Name $_.Name -QueryTerms $queryTerms }
            }, Category, Name)
        $groups = @($orderedFamilies | Select-Object -First 10)

        Send-Json -Context $Context -StatusCode 200 -Value @{
            query = $query
            queryTerms = $queryTerms
            matchedTerms = $matchedTerms
            count = $matches.Count
            groupCount = $orderedFamilies.Count
            groups = $groups
            retrievedAt = $script:RetrievedAt
            warning = $script:DataWarning
            source = if (@($script:UserImportRecords).Count -gt 0) { "$($script:DataSource) + lokale Benutzerimporte" } else { $script:DataSource }
            provenance = (Get-SourceProvenance)
        }
        return
    }

    if ($path -eq '/api/detail') {
        $parameters = [System.Web.HttpUtility]::ParseQueryString($Context.Request.Url.Query)
        $id = $parameters.Get('id')
        $version = $parameters.Get('version')
        $application = $parameters.Get('useCase')
        $catalog = Get-SearchableCatalog

        $record = $catalog.Records | Where-Object { $_.Id -eq $id -and $_.Version -eq $version } | Select-Object -First 1
        if ($null -eq $record) {
            Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Dieser Datensatz ist im geladenen Katalog nicht verfügbar.' }
            return
        }

        $category = $record.Category
        $comparisonCanBeMade = $null -ne $record.Gwp -and
            -not [string]::IsNullOrWhiteSpace($category) -and
            -not [string]::IsNullOrWhiteSpace($record.Unit) -and
            -not [string]::IsNullOrWhiteSpace($record.ReferenceAmount) -and
            $record.Validity -eq 'valid'
        $comparisonReason = ''
        if ($null -eq $record.Gwp) {
            $comparisonReason = 'Für diesen Datensatz ist kein GWP-Wert vorhanden.'
        }
        elseif ([string]::IsNullOrWhiteSpace($category) -or
            [string]::IsNullOrWhiteSpace($record.Unit) -or
            [string]::IsNullOrWhiteSpace($record.ReferenceAmount)) {
            $comparisonReason = 'Kategorie, Einheit oder Bezugsmenge fehlen.'
        }
        elseif ($record.Validity -eq 'expired') {
            $comparisonReason = 'Die Gültigkeit dieses Datensatzes ist abgelaufen.'
        }
        elseif ($record.Validity -ne 'valid') {
            $comparisonReason = 'Für diesen Datensatz fehlt eine auswertbare Gültigkeitsangabe.'
        }
        $group = @()
        if ($comparisonCanBeMade) {
            $group = @($catalog.Records | Where-Object {
                $_.Category -eq $category -and
                $_.Unit -eq $record.Unit -and
                $_.ReferenceAmount -eq $record.ReferenceAmount -and
                $_.ComparisonClass -eq $record.ComparisonClass -and
                $_.Validity -eq 'valid' -and
                $null -ne $_.Gwp
            })
        }
        $alternatives = @()
        if ($comparisonCanBeMade) {
            $alternatives = @($group |
                Where-Object {
                    $_.Id -ne $record.Id -and
                    $_.Gwp -lt $record.Gwp
                } |
                Sort-Object -Property Gwp |
                Select-Object -First 1 |
                ForEach-Object {
                    [pscustomobject]@{
                        Item = Get-ItemView -Record $_
                        SameFamily = ($_.FamilyName -eq $record.FamilyName)
                        Metrics = Get-MetricComparisons -SelectedMetrics $record.Metrics -AlternativeMetrics $_.Metrics
                    }
                })
        }

        Send-Json -Context $Context -StatusCode 200 -Value @{
            item = Get-ItemView -Record $record
            rating = (Get-ItemView -Record $record).Rating
            comparison = @{
                category = $category
                technicalClass = $record.ComparisonClass
                unit = $record.Unit
                referenceAmount = $record.ReferenceAmount
                count = $group.Count
                comparable = $comparisonCanBeMade
                reason = $comparisonReason
            }
            materialAlternative = Get-MaterialAlternativeAssessment -Record $record -Application $application
            alternatives = $alternatives
            retrievedAt = $script:RetrievedAt
            warning = $script:DataWarning
            source = if (@($script:UserImportRecords).Count -gt 0) { "$($script:DataSource) + lokale Benutzerimporte" } else { $script:DataSource }
            provenance = (Get-SourceProvenance)
        }
        return
    }

    $staticFiles = @{
        '/' = 'index.html'
        '/styles.css' = 'styles.css'
        '/swiss.css' = 'swiss.css'
        '/app.js' = 'app.js'
        '/ifc.mjs' = 'ifc.mjs'
        '/ifc-disclosure.mjs' = 'ifc-disclosure.mjs'
        '/demo-data.mjs' = 'demo-data.mjs'
        '/hero-landscape.svg' = 'hero-landscape.svg'
        '/tree-cursor.svg' = 'tree-cursor.svg'
    }
    if ($staticFiles.ContainsKey($path)) {
        $file = Join-Path (Join-Path $script:Root 'public') $staticFiles[$path]
        $contentType = if ($path -eq '/') { 'text/html; charset=utf-8' } elseif ($path -eq '/app.js' -or $path -eq '/ifc.mjs' -or $path -eq '/ifc-disclosure.mjs' -or $path -eq '/demo-data.mjs') { 'text/javascript; charset=utf-8' } elseif ($path -eq '/hero-landscape.svg' -or $path -eq '/tree-cursor.svg') { 'image/svg+xml; charset=utf-8' } else { 'text/css; charset=utf-8' }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        Send-Response -Context $Context -StatusCode 200 -ContentType $contentType -Body $bytes
        return
    }

    Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Diese Seite wurde nicht gefunden.' }
}

if (-not $script:TestMode) {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add('http://127.0.0.1:8765/')
    try {
        $listener.Start()
    }
    catch {
        Write-Error "Der lokale Webserver konnte nicht gestartet werden. Ist Port 8765 bereits belegt? $($_.Exception.Message)"
        exit 1
    }

    Write-Host 'Die App laeuft lokal unter http://127.0.0.1:8765/'
    Write-Host 'Beenden: dieses Fenster schliessen oder Strg+C druecken.'
    Start-Process 'http://127.0.0.1:8765/'

    try {
        while ($listener.IsListening) {
            $context = $listener.GetContext()
            try {
                Handle-Request -Context $context
            }
            catch {
                Write-Host ("Anfrage fehlgeschlagen: {0}" -f $_.Exception.Message) -ForegroundColor Red
                if ($context.Response.OutputStream.CanWrite) {
                    try {
                        Send-Json -Context $context -StatusCode 500 -Value @{
                            error = "Die Anfrage konnte nicht verarbeitet werden: $($_.Exception.Message)"
                        }
                    }
                    catch {
                        Write-Host ("Die Clientverbindung wurde vor der Fehlerantwort geschlossen: {0}" -f $_.Exception.Message)
                    }
                }
            }
        }
    }
    finally {
        $listener.Stop()
        $listener.Close()
    }
}
