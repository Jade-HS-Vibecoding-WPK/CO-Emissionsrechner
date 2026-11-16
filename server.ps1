$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Web
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:CacheDirectory = Join-Path $env:LOCALAPPDATA 'CO-Emissionsrechner'
$script:CacheFile = Join-Path $script:CacheDirectory 'oekobaudat-2024-II.csv'
$script:DataUrl = 'https://www.oekobaudat.de/OEKOBAU.DAT/resource/datastocks/cc64f7e1-14d8-4a57-b11b-2cf03d200c82/exportCSV'
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
                Category = $category
                Unit = Get-Field -Fields $fields -Columns $columns -Name 'Bezugseinheit'
                ReferenceAmount = Get-Field -Fields $fields -Columns $columns -Name 'Bezugsgroesse'
                Gwp = Convert-ToNumber (Get-Field -Fields $fields -Columns $columns -Name 'GWPtotal (A2)')
                Owner = Get-Field -Fields $fields -Columns $columns -Name 'Declaration owner'
                ReferenceYear = Get-Field -Fields $fields -Columns $columns -Name 'Referenzjahr'
                ValidUntil = Get-Field -Fields $fields -Columns $columns -Name 'Gueltig bis'
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
    Write-Host ("OEKOBAUDAT bereit: {0} vergleichbare Datensaetze (EN 15804+A2, A1-A3)." -f $script:Dataset.Length)
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
        Category = $Record.Category
        Unit = $Record.Unit
        ReferenceAmount = $Record.ReferenceAmount
        Gwp = $gwp
        Owner = $Record.Owner
        ReferenceYear = $Record.ReferenceYear
        ValidUntil = $Record.ValidUntil
        Registration = $Record.Registration
        Url = $Record.Url
        Metrics = @($Record.Metrics)
    }
}

function Get-Rating {
    param(
        [object[]]$Group,
        [string]$RecordId,
        [string]$Version
    )

    $ordered = @($Group | Sort-Object -Property Gwp, Name)
    $count = $ordered.Count
    if ($count -lt 3) {
        return [pscustomobject]@{
            Color = 'unknown'
            Label = 'Zu wenige Vergleichsdaten'
            Rank = $null
            Count = $count
        }
    }

    for ($i = 0; $i -lt $count; $i++) {
        if ($ordered[$i].Id -eq $RecordId -and $ordered[$i].Version -eq $Version) {
            $position = ($i + 0.5) / $count
            if ($position -le (1.0 / 3.0)) {
                $color = 'good'
                $label = 'Niedriger im Vergleich'
            }
            elseif ($position -le (2.0 / 3.0)) {
                $color = 'medium'
                $label = 'Mittlerer Vergleichswert'
            }
            else {
                $color = 'poor'
                $label = 'Hoeher im Vergleich'
            }

            return [pscustomobject]@{
                Color = $color
                Label = $label
                Rank = $i + 1
                Count = $count
            }
        }
    }

    return [pscustomobject]@{
        Color = 'unknown'
        Label = 'Kein vergleichbarer GWP-Wert'
        Rank = $null
        Count = $count
    }
}

function Handle-Request {
    param([System.Net.HttpListenerContext]$Context)

    $path = $Context.Request.Url.AbsolutePath
    if ($path -eq '/api/health') {
        Send-Json -Context $Context -StatusCode 200 -Value @{
            ready = $true
            source = 'OEKOBAUDAT 2024-II'
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
        $items = @($matches |
            Sort-Object -Property @{ Expression = { if ($_.Name.StartsWith($query, [System.StringComparison]::OrdinalIgnoreCase)) { 0 } else { 1 } } }, Name |
            Select-Object -First 30 |
            ForEach-Object { Get-ItemView -Record $_ })

        Send-Json -Context $Context -StatusCode 200 -Value @{
            query = $query
            count = $matches.Count
            items = $items
            retrievedAt = $script:RetrievedAt
            warning = $script:DataWarning
            source = 'OEKOBAUDAT 2024-II, EN 15804+A2, Modul A1-A3'
        }
        return
    }

    if ($path -eq '/api/detail') {
        $parameters = [System.Web.HttpUtility]::ParseQueryString($Context.Request.Url.Query)
        $id = $parameters.Get('id')
        $version = $parameters.Get('version')
        Ensure-Dataset

        $record = $script:Dataset | Where-Object { $_.Id -eq $id -and $_.Version -eq $version } | Select-Object -First 1
        if ($null -eq $record) {
            Send-Json -Context $Context -StatusCode 404 -Value @{ error = 'Dieser Datensatz ist im geladenen OEKOBAUDAT-Stand nicht verfuegbar.' }
            return
        }

        $categoryTop = ($record.Category -split ' / ')[0]
        $group = @($script:Dataset | Where-Object {
            $_.Category.StartsWith($categoryTop, [System.StringComparison]::OrdinalIgnoreCase) -and
            $_.Unit -eq $record.Unit -and
            $_.ReferenceAmount -eq $record.ReferenceAmount -and
            $null -ne $_.Gwp
        })
        $rating = Get-Rating -Group $group -RecordId $record.Id -Version $record.Version
        $alternatives = @($group |
            Where-Object { $_.Id -ne $record.Id } |
            Sort-Object -Property Gwp |
            Select-Object -First 5 |
            ForEach-Object {
                $alternativeRating = Get-Rating -Group $group -RecordId $_.Id -Version $_.Version
                [pscustomobject]@{
                    Item = Get-ItemView -Record $_
                    Rating = $alternativeRating
                }
            })

        Send-Json -Context $Context -StatusCode 200 -Value @{
            item = Get-ItemView -Record $record
            rating = $rating
            comparison = @{
                category = $categoryTop
                unit = $record.Unit
                referenceAmount = $record.ReferenceAmount
                count = $group.Count
            }
            alternatives = $alternatives
            retrievedAt = $script:RetrievedAt
            warning = $script:DataWarning
            source = 'OEKOBAUDAT 2024-II, EN 15804+A2, Modul A1-A3'
        }
        return
    }

    $staticFiles = @{
        '/' = 'index.html'
        '/styles.css' = 'styles.css'
        '/app.js' = 'app.js'
    }
    if ($staticFiles.ContainsKey($path)) {
        $file = Join-Path (Join-Path $script:Root 'public') $staticFiles[$path]
        $contentType = if ($path -eq '/') { 'text/html; charset=utf-8' } elseif ($path -eq '/app.js') { 'text/javascript; charset=utf-8' } else { 'text/css; charset=utf-8' }
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
