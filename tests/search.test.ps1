$ErrorActionPreference = 'Stop'
$script:TestMode = $true
. (Join-Path $PSScriptRoot '..\server.ps1')

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message (actual: '$Actual', expected: '$Expected')"
    }
}

function Assert-Contains {
    param(
        [string[]]$Values,
        [string]$Expected,
        [string]$Message
    )

    if ($Values -notcontains $Expected) {
        throw "$Message (missing: '$Expected')"
    }
}

$releaseHtml = @'
<a href="https://www.oekobaudat.de/OEKOBAU.DAT/resource/datastocks/old-id/exportCSV?decimalSeparator=comma">&#214;KOBAUDAT 2023-II als CSV-Datei mit Komma</a>
<a href="https://www.oekobaudat.de/OEKOBAU.DAT/resource/datastocks/bca3670a-8dcf-44d0-be1f-0633d9ba1a75/exportCSV">&#214;KOBAUDAT 2024-III als CSV-Datei mit Punkt als Dezimaltrenner</a>
'@
$export = Get-OfficialExportInfo -Html $releaseHtml
Assert-Equal -Actual $export.Release -Expected '2024-III' -Message 'The current dot-decimal official export should be selected'
Assert-Equal -Actual $export.DataStockId -Expected 'bca3670a-8dcf-44d0-be1f-0633d9ba1a75' -Message 'The stock ID should come from the official link'
Assert-Equal -Actual $export.DownloadUrl -Expected 'https://www.oekobaudat.de/OEKOBAU.DAT/resource/datastocks/bca3670a-8dcf-44d0-be1f-0633d9ba1a75/exportCSV' -Message 'The comma-decimal export must not be used'

$concreteTerms = @(Get-MaterialQueryTerms -Query 'concrete')
Assert-Contains -Values $concreteTerms -Expected 'Beton' -Message 'English material names should expand to German ÖKOBAUDAT terms'
$fiberTerms = @(Get-MaterialQueryTerms -Query 'Holzfaserdammstoff')
Assert-Contains -Values $fiberTerms -Expected 'wood fibre insulation' -Message 'German material names should expand to English synonyms'
$unknownTerms = @(Get-MaterialQueryTerms -Query 'unbekanntes Material')
Assert-Equal -Actual $unknownTerms.Count -Expected 1 -Message 'Unknown materials should not receive guessed aliases'

$record = [pscustomobject]@{
    Name = 'Beton'
    Category = 'Bauprodukte / Beton'
}
$matched = @(Get-RecordMatchedTerms -Record $record -QueryTerms $concreteTerms)
Assert-Contains -Values $matched -Expected 'Beton' -Message 'Expanded terms should be used for record matching'
$otherMaterial = [pscustomobject]@{
    Name = 'Gipskarton'
    Category = 'Bauprodukte / Gipskarton'
}
$recordSearch = Find-MaterialRecords -Records @($record, $otherMaterial) -Query 'concrete'
Assert-Equal -Actual $recordSearch.Records.Count -Expected 1 -Message 'Expanded search should return only matching material records'
Assert-Contains -Values $recordSearch.MatchedTerms -Expected 'Beton' -Message 'Search results should report the alias that matched'
$catalogIndex = Build-MaterialCatalogIndex -Records @($record, $otherMaterial)
$indexedRecordSearch = Find-MaterialRecords -Records @($record, $otherMaterial) -Index $catalogIndex -Query 'concrete'
Assert-Equal -Actual $indexedRecordSearch.Records.Count -Expected 1 -Message 'The local catalog index should preserve alias search behavior'
Assert-Equal -Actual $indexedRecordSearch.Records[0].Name -Expected 'Beton' -Message 'The local catalog index should return its source record'

$validCsv = [System.IO.Path]::GetTempFileName()
$invalidCsv = [System.IO.Path]::GetTempFileName()
$metadataFile = [System.IO.Path]::GetTempFileName()
try {
    $csvContent = @"
UUID;Version;Name (de);GWPtotal (A2);Konformitaet;Modul
process-1;1.0;Beton;0.12;EN 15804+A2;A1-A3
"@
    [System.IO.File]::WriteAllText($validCsv, $csvContent, [System.Text.Encoding]::ASCII)
    Assert-Equal -Actual (Test-OekoCsvFile -Path $validCsv) -Expected $true -Message 'A compatible official CSV should pass validation'

    $invalidContent = @"
UUID;Version;Name (de);GWPtotal (A2);Konformitaet;Modul
process-1;1.0;Beton;0.12;EN 15804+A2;A4
"@
    [System.IO.File]::WriteAllText($invalidCsv, $invalidContent, [System.Text.Encoding]::ASCII)
    $invalidRejected = $false
    try {
        [void](Test-OekoCsvFile -Path $invalidCsv)
    }
    catch {
        $invalidRejected = $true
    }
    Assert-Equal -Actual $invalidRejected -Expected $true -Message 'A CSV without the requested scope should be rejected'

    $cacheMetadata = [pscustomobject]@{
        SourceName = 'OEKOBAUDAT'
        Release = '2024-III'
        DataStockId = 'bca3670a-8dcf-44d0-be1f-0633d9ba1a75'
        DownloadUrl = $export.DownloadUrl
    }
    Write-OekoCacheMetadata -Path $metadataFile -Metadata $cacheMetadata
    $cachedMetadata = Read-OekoCacheMetadata -Path $metadataFile
    Assert-Equal -Actual $cachedMetadata.Release -Expected '2024-III' -Message 'The cache sidecar should retain the source release'
    Assert-Equal -Actual $cachedMetadata.DataStockId -Expected $export.DataStockId -Message 'The cache sidecar should retain the verified data stock'

    $script:SourceMetadata = $cachedMetadata
    $script:RetrievedAt = '2026-11-17'
    $script:CacheStatus = 'current-cache'
    $script:CatalogStatus = 'ready'
    $script:CatalogManifest = [pscustomobject]@{ RecordCount = 1 }
    $provenance = Get-SourceProvenance
    Assert-Equal -Actual $provenance.release -Expected '2024-III' -Message 'API provenance should expose the source release'
    Assert-Equal -Actual $provenance.cacheStatus -Expected 'current-cache' -Message 'API provenance should expose cache state'
    Assert-Equal -Actual $provenance.catalogStatus -Expected 'ready' -Message 'API provenance should expose local catalog state'
    Assert-Equal -Actual $provenance.catalogRecordCount -Expected 1 -Message 'API provenance should expose the searchable catalog size'
    Assert-Equal -Actual $provenance.licenseStatus -Expected 'reuse-terms-not-independently-verified' -Message 'API provenance should disclose unverified reuse terms'
    if ([string]::IsNullOrWhiteSpace($provenance.usageNotice)) {
        throw 'API provenance should include a source usage notice.'
    }
    $expectedSourceName = ([string][char]214) + 'KOBAUDAT'
    Assert-Equal -Actual $provenance.sourceName -Expected $expectedSourceName -Message 'API provenance should identify the data source'

    $view = Get-SearchItemView -Record ([pscustomobject]@{
        Id = 'process-1'
        Version = '1.0'
        Name = 'Beton'
        FamilyName = 'Beton'
        ComparisonClass = 'Beton'
        Category = 'Bauprodukte / Beton'
        CategoryGroup = 'Bauprodukte'
        Unit = 'kg'
        ReferenceAmount = '1'
        Gwp = 0.12
        Owner = 'Test'
        ReferenceYear = '2024'
        ValidUntil = '2030'
        Validity = 'valid'
        RatingGroup = 'nicht vergleichbar'
        RatingRank = $null
        RatingCount = 0
        Registration = ''
        Url = 'https://www.oekobaudat.de/OEKOBAU.DAT/resource/processes/process-1?version=1.0'
        SourceName = $expectedSourceName
        SourceUrl = $script:ReleasePageUrl
        DataStockId = $cachedMetadata.DataStockId
        DataStockVersion = $cachedMetadata.Release
        RetrievedAt = $script:RetrievedAt
        CacheStatus = $script:CacheStatus
        Metrics = @()
    }) -QueryTerms $concreteTerms
    Assert-Equal -Actual $view.SourceName -Expected $expectedSourceName -Message 'Search items should retain their source'
    Assert-Equal -Actual $view.DataStockVersion -Expected '2024-III' -Message 'Search items should retain their data stock version'
    Assert-Contains -Values $view.MatchedQueries -Expected 'Beton' -Message 'Search items should report the query term that matched'

    $cacheDirectory = Join-Path $env:TEMP ("co-emissions-search-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $cacheDirectory | Out-Null
    $oldCacheDirectory = $script:CacheDirectory
    $oldCacheFile = $script:CacheFile
    $oldCacheMetadataFile = $script:CacheMetadataFile
    $oldCatalogIndex = $script:CatalogIndex
    $oldCatalogManifest = $script:CatalogManifest
    $oldCatalogStatus = $script:CatalogStatus
    $script:CacheDirectory = $cacheDirectory
    $script:CacheFile = Join-Path $cacheDirectory 'oekobaudat.csv'
    $script:CacheMetadataFile = Join-Path $cacheDirectory 'oekobaudat.metadata.json'
    $script:Dataset = $null
    $script:CatalogIndex = $null
    $script:CatalogManifest = $null
    $script:CatalogStatus = 'not-loaded'
    $script:TestReleaseHtml = $releaseHtml
    $script:TestExpectedDownloadUrl = $export.DownloadUrl
    $script:TestCsvContent = @"
UUID;Version;Name (de);Kategorie (original);Bezugseinheit;Bezugsgroesse;GWPtotal (A2);Konformitaet;Modul;Gueltig bis;Declaration owner;Referenzjahr;Registrierungsnummer
process-1;1.0;Beton;Bauprodukte / Beton;kg;1;0.12;EN 15804+A2;A1-A3;2030;Test owner;2024;TEST
"@
    function Invoke-WebRequest {
        param(
            [string]$Uri,
            [string]$OutFile,
            [switch]$UseBasicParsing,
            [int]$TimeoutSec
        )

        if ($Uri -eq $script:ReleasePageUrl) {
            if ($TimeoutSec -ne 15) {
                throw 'The official release-page request should have a bounded timeout.'
            }
            return [pscustomobject]@{ Content = $script:TestReleaseHtml }
        }
        if ($Uri -eq $script:TestExpectedDownloadUrl) {
            if ($TimeoutSec -ne 60) {
                throw 'The official catalog download should have a bounded timeout.'
            }
            [System.IO.File]::WriteAllText($OutFile, $script:TestCsvContent, [System.Text.Encoding]::ASCII)
            return
        }
        throw "Unexpected URL in source test: $Uri"
    }

    try {
        Ensure-Dataset
        Assert-Equal -Actual $script:SourceMetadata.Release -Expected '2024-III' -Message 'Refresh should cache the release discovered from the official page'
        Assert-Equal -Actual $script:SourceMetadata.DataStockId -Expected $export.DataStockId -Message 'Refresh should cache the official data stock ID'
        Assert-Equal -Actual $script:CacheStatus -Expected 'updated' -Message 'Successful refresh should report updated cache state'
        Assert-Equal -Actual $script:Dataset.Count -Expected 1 -Message 'Validated CSV records should load into the search dataset'
        Assert-Equal -Actual $script:CatalogIndex.Count -Expected 1 -Message 'The searchable local catalog should index validated source records'
        Assert-Equal -Actual $script:CatalogStatus -Expected 'ready' -Message 'The local catalog should report a ready manifest'

        $catalogDirectory = Join-Path $cacheDirectory 'catalog'
        $catalogManifestPath = Join-Path $catalogDirectory 'manifest.json'
        if (-not (Test-Path -LiteralPath $catalogManifestPath)) {
            throw 'The local catalog should persist a source manifest under its app-data directory.'
        }
        $catalogManifest = Read-OekoCacheMetadata -Path $catalogManifestPath
        Assert-Equal -Actual $catalogManifest.RecordCount -Expected 1 -Message 'The catalog manifest should record indexed record count'
        Assert-Equal -Actual $catalogManifest.Release -Expected '2024-III' -Message 'The catalog manifest should preserve the source release'
        Assert-Equal -Actual $catalogManifest.CacheStatus -Expected 'updated' -Message 'The catalog manifest should preserve cache state'
        Assert-Equal -Actual $catalogManifest.RecordsPersisted -Expected $false -Message 'The catalog should not duplicate source records on disk'
        if ($catalogManifest.SourceFileSha256.Length -ne 64) {
            throw 'The catalog manifest should record a SHA-256 hash of the source snapshot.'
        }
        Assert-Equal -Actual @(Get-ChildItem -LiteralPath $catalogDirectory -File).Count -Expected 1 -Message 'The catalog directory should contain metadata only, not a copied dataset'

        function Invoke-WebRequest {
            param(
                [string]$Uri,
                [string]$OutFile,
                [switch]$UseBasicParsing,
                [int]$TimeoutSec
            )
            throw 'simulated offline source'
        }
        $script:Dataset = $null
        Ensure-Dataset
        Assert-Equal -Actual $script:CacheStatus -Expected 'release-unverified-cache' -Message 'A release-page failure should use the existing cache with an explicit status'
        Assert-Equal -Actual $script:SourceMetadata.Release -Expected '2024-III' -Message 'Offline fallback should preserve cached provenance'
        $offlineManifest = Read-OekoCacheMetadata -Path $catalogManifestPath
        Assert-Equal -Actual $offlineManifest.CacheStatus -Expected 'release-unverified-cache' -Message 'The catalog manifest should record offline cache status'
        if ([string]::IsNullOrWhiteSpace($script:DataWarning)) {
            throw 'Offline fallback should expose a source warning.'
        }

        Remove-Item -LiteralPath $catalogDirectory -Recurse
        [System.IO.File]::WriteAllText($catalogDirectory, 'conflicting-file', [System.Text.Encoding]::ASCII)
        $script:Dataset = $null
        $script:CatalogIndex = $null
        $script:CatalogManifest = $null
        Ensure-Dataset
        Assert-Equal -Actual $script:CatalogStatus -Expected 'manifest-write-failed' -Message 'A manifest write failure should be reported without discarding loaded records'
        Assert-Equal -Actual $script:Dataset.Count -Expected 1 -Message 'A catalog manifest failure should leave the source dataset searchable'
        if ($script:DataWarning -notmatch 'Quellenmanifest') {
            throw 'A local catalog manifest failure should be included in the warning.'
        }
    }
    finally {
        Remove-Item Function:\Invoke-WebRequest -ErrorAction SilentlyContinue
        $script:CacheDirectory = $oldCacheDirectory
        $script:CacheFile = $oldCacheFile
        $script:CacheMetadataFile = $oldCacheMetadataFile
        $script:CatalogIndex = $oldCatalogIndex
        $script:CatalogManifest = $oldCatalogManifest
        $script:CatalogStatus = $oldCatalogStatus
        foreach ($path in @(
            (Join-Path $cacheDirectory 'oekobaudat.csv'),
            (Join-Path $cacheDirectory 'oekobaudat.metadata.json'),
            (Join-Path $cacheDirectory 'oekobaudat.metadata.json.download'),
            (Join-Path $cacheDirectory 'oekobaudat.csv.download')
        )) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path
            }
        }
        $catalogDirectory = Join-Path $cacheDirectory 'catalog'
        if (Test-Path -LiteralPath $catalogDirectory) {
            Remove-Item -LiteralPath $catalogDirectory -Recurse
        }
        if (Test-Path -LiteralPath $cacheDirectory) {
            Remove-Item -LiteralPath $cacheDirectory
        }
    }
}
finally {
    foreach ($path in @($validCsv, $invalidCsv, $metadataFile, "$metadataFile.download")) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path
        }
    }
}

Write-Output 'OEKOBAUDAT search tests passed.'
