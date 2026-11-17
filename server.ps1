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
        $Record.Name.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $Record.Category.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
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
        $Entry.Name.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
        $Entry.Category.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
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
        $releasePage = Invoke-WebRequest -Uri $script:ReleasePageUrl -UseBasicParsing
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
            Invoke-WebRequest -Uri $officialExport.DownloadUrl -OutFile $downloadFile -UseBasicParsing
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

function Handle-Request {
    param([System.Net.HttpListenerContext]$Context)

    $path = $Context.Request.Url.AbsolutePath
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

        Ensure-Dataset
        $search = Find-MaterialRecords -Records $script:Dataset -Index $script:CatalogIndex -Query $query
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
            source = $script:DataSource
            provenance = (Get-SourceProvenance)
        }
        return
    }

    if ($path -eq '/api/detail') {
        $parameters = [System.Web.HttpUtility]::ParseQueryString($Context.Request.Url.Query)
        $id = $parameters.Get('id')
        $version = $parameters.Get('version')
        $application = $parameters.Get('useCase')
        Ensure-Dataset

        $record = $script:Dataset | Where-Object { $_.Id -eq $id -and $_.Version -eq $version } | Select-Object -First 1
        if ($null -eq $record) {
            Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Dieser Datensatz ist im geladenen OEKOBAUDAT-Stand nicht verfuegbar.' }
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
            $group = @($script:Dataset | Where-Object {
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
            source = $script:DataSource
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
        '/hero-landscape.svg' = 'hero-landscape.svg'
    }
    if ($staticFiles.ContainsKey($path)) {
        $file = Join-Path (Join-Path $script:Root 'public') $staticFiles[$path]
        $contentType = if ($path -eq '/') { 'text/html; charset=utf-8' } elseif ($path -eq '/app.js' -or $path -eq '/ifc.mjs') { 'text/javascript; charset=utf-8' } elseif ($path -eq '/hero-landscape.svg') { 'image/svg+xml; charset=utf-8' } else { 'text/css; charset=utf-8' }
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
                    Send-Json -Context $context -StatusCode 500 -Value @{
                        error = "Die OEKOBAUDAT-Daten konnten nicht verarbeitet werden: $($_.Exception.Message)"
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
