$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Web
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CacheDirectory = Join-Path $env:LOCALAPPDATA 'CO-Emissionsrechner'
$script:CacheFile = Join-Path $script:CacheDirectory 'oekobaudat.csv'
$script:DataUrl = 'https://www.oekobaudat.de/OEKOBAU.DAT/resource/datastocks/cc64f7e1-14d8-4a57-b11b-2cf03d200c82/exportCSV'
$script:DataSource = 'OEKOBAUDAT-CSV-Export, EN 15804+A2, Modul A1-A3'
$script:Dataset = $null
$script:RetrievedAt = $null
$script:DataWarning = $null

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
    if ($null -ne $script:Dataset) {
        return
    }

    if (-not (Test-Path -LiteralPath $script:CacheDirectory)) {
        New-Item -ItemType Directory -Path $script:CacheDirectory -Force | Out-Null
    }

    $cacheExists = Test-Path -LiteralPath $script:CacheFile
    $cacheIsFresh = $false
    if ($cacheExists) {
        $cacheIsFresh = (Get-Item -LiteralPath $script:CacheFile).LastWriteTimeUtc -gt [DateTime]::UtcNow.AddDays(-1)
    }

    if (-not $cacheIsFresh) {
        try {
            Write-Host 'Lade den aktuellen OEKOBAUDAT-Export herunter ...'
            $downloadFile = "$($script:CacheFile).download"
            Invoke-WebRequest -Uri $script:DataUrl -OutFile $downloadFile -UseBasicParsing
            Move-Item -LiteralPath $downloadFile -Destination $script:CacheFile -Force
        }
        catch {
            if ($downloadFile -and (Test-Path -LiteralPath $downloadFile)) {
                Remove-Item -LiteralPath $downloadFile
            }
            if (-not (Test-Path -LiteralPath $script:CacheFile)) {
                throw "Der OEKOBAUDAT-Export konnte nicht geladen werden: $($_.Exception.Message)"
            }

            $script:DataWarning = 'Die Aktualisierung ist fehlgeschlagen. Es werden zwischengespeicherte Daten verwendet.'
            Write-Warning $script:DataWarning
        }
    }

    $script:RetrievedAt = (Get-Item -LiteralPath $script:CacheFile).LastWriteTimeUtc.ToString('yyyy-MM-dd')
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

    Write-Host ("OEKOBAUDAT bereit: {0} Datensaetze; relative Gruppen nur innerhalb vergleichbarer Datensaetze." -f $script:Dataset.Length)
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
        Metrics = @($Record.Metrics)
    }
}

function Get-SearchItemView {
    param([object]$Record)

    $item = Get-ItemView -Record $Record
    $item.PSObject.Properties.Remove('Metrics')
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
        $matches = @($script:Dataset | Where-Object {
            $_.Name.IndexOf($query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.Category.IndexOf($query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
        })
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
                    Items = @($peerRecords | Select-Object -First 5 | ForEach-Object { Get-SearchItemView -Record $_ })
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
                Expression = {
                    if ($_.Name.Equals($query, [System.StringComparison]::OrdinalIgnoreCase)) { 0 }
                    elseif ($_.Name.StartsWith("$query ", [System.StringComparison]::OrdinalIgnoreCase)) { 1 }
                    elseif ($_.Name.StartsWith($query, [System.StringComparison]::OrdinalIgnoreCase)) { 2 }
                    else { 3 }
                }
            }, Category, Name)
        $groups = @($orderedFamilies | Select-Object -First 10)

        Send-Json -Context $Context -StatusCode 200 -Value @{
            query = $query
            count = $matches.Count
            groupCount = $orderedFamilies.Count
            groups = $groups
            retrievedAt = $script:RetrievedAt
            warning = $script:DataWarning
            source = $script:DataSource
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
        }
        return
    }

    $staticFiles = @{
        '/' = 'index.html'
        '/styles.css' = 'styles.css'
        '/swiss.css' = 'swiss.css'
        '/app.js' = 'app.js'
        '/hero-landscape.svg' = 'hero-landscape.svg'
    }
    if ($staticFiles.ContainsKey($path)) {
        $file = Join-Path (Join-Path $script:Root 'public') $staticFiles[$path]
        $contentType = if ($path -eq '/') { 'text/html; charset=utf-8' } elseif ($path -eq '/app.js') { 'text/javascript; charset=utf-8' } elseif ($path -eq '/hero-landscape.svg') { 'image/svg+xml; charset=utf-8' } else { 'text/css; charset=utf-8' }
        $bytes = [System.IO.File]::ReadAllBytes($file)
        Send-Response -Context $Context -StatusCode 200 -ContentType $contentType -Body $bytes
        return
    }

    Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Diese Seite wurde nicht gefunden.' }
}

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
