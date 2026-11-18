$ErrorActionPreference = 'Stop'
$script:TestMode = $true
. (Join-Path $PSScriptRoot '..\server.ps1')

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "$Message (actual: '$Actual', expected: '$Expected')"
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert-Equal -Actual $threw -Expected $true -Message $Message
}

$temporaryDirectory = Join-Path $env:TEMP ("co-emissions-import-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
$script:CacheDirectory = $temporaryDirectory
$script:UserImportStoreFile = Join-Path $temporaryDirectory 'user-imports.json'
$script:UserImportStateLoaded = $false
$script:UserImportBatches = @()
$script:UserImportRecords = @()
$script:PendingUserImports = @{}
$script:CombinedCatalogIndex = $null

try {
    $headers = 'SourceName,SourceRecordId,Version,ProductName,Category,Unit,ReferenceAmount,GwpKgCO2e,Standard,Modules,ValidUntil,SourceUrl,LicenseNotice,SolarReflectancePercent,SolarReflectanceMethod,SolarReflectanceWavelength'
    $validCsv = "$headers`r`nExample EPD,EPD-001,1.0,Pine panel,Wood products / Panels,kg,1,25.5,EN 15804+A2,A1-A3,2030,https://example.org/epd,Permitted for local reuse,45.2,EN 410,300-2500 nm"
    $parsed = ConvertFrom-UserCatalogCsv -Text $validCsv
    Assert-Equal -Actual $parsed.Records.Count -Expected 1 -Message 'A complete source-aware CSV row should parse'
    Assert-Equal -Actual $parsed.Errors.Count -Expected 0 -Message 'A valid source-aware CSV row should have no validation errors'
    Assert-Equal -Actual $parsed.Records[0].SolarReflectance.Value -Expected 45.2 -Message 'Solar reflectance should retain its stated value'
    Assert-Equal -Actual $parsed.Records[0].Standard -Expected 'EN 15804+A2' -Message 'GWP standard should remain explicit'
    Assert-Equal -Actual $parsed.Records[0].Modules -Expected 'A1-A3' -Message 'GWP modules should remain explicit'

    $invalidCsv = $validCsv.Replace(',kg,1,25.5,EN 15804+A2,A1-A3,', ',unknown,1,25.5,EN 15804+A2,A4,')
    $invalid = ConvertFrom-UserCatalogCsv -Text $invalidCsv
    Assert-Equal -Actual $invalid.Records.Count -Expected 0 -Message 'Unsupported units and life-cycle modules must not enter the catalog'
    if (@($invalid.Errors | Where-Object { $_.field -eq 'Unit' }).Count -eq 0 -or
        @($invalid.Errors | Where-Object { $_.field -eq 'Standard' }).Count -eq 0) {
        throw 'Invalid unit and module errors should be reported by field.'
    }
    $invalidReflectance = ConvertFrom-UserCatalogCsv -Text $validCsv.Replace(',45.2,EN 410,', ',101,EN 410,')
    Assert-Equal -Actual $invalidReflectance.Records.Count -Expected 0 -Message 'Solar-reflectance values outside the physical percentage range must be rejected'
    $solarOnlyRow = @(
        'Solar source', 'SOLAR-001', '1.0', 'Solar facade panel', 'Envelope / Panels',
        '', '', '', '', '', '', 'https://example.org/solar', 'Permitted for local reuse',
        '45.2', 'EN 410', '300-2500 nm'
    ) -join ','
    $solarOnlyPreview = New-UserImportPreview -CsvText "$headers`r`n$solarOnlyRow"
    Assert-Equal -Actual $solarOnlyPreview.validRowCount -Expected 1 -Message 'A fully sourced solar-only row should remain available as non-GWP data'
    [void](Remove-PendingUserImport -PreviewId $solarOnlyPreview.previewId)

    $preview = New-UserImportPreview -CsvText $validCsv
    Assert-Equal -Actual $preview.validRowCount -Expected 1 -Message 'A valid row should be offered for explicit import confirmation'
    Assert-Throws -Action { Confirm-UserImport -PreviewId $preview.previewId -RightsConfirmed $false } -Message 'Import should require rights confirmation'
    $imported = Confirm-UserImport -PreviewId $preview.previewId -RightsConfirmed $true
    Assert-Equal -Actual $imported.importedRecordCount -Expected 1 -Message 'Confirm should persist the valid row'
    Assert-Equal -Actual $script:UserImportRecords.Count -Expected 1 -Message 'Confirmed rows should join the local searchable catalog'
    Assert-Equal -Actual $script:UserImportRecords[0].RecordKind -Expected 'user-import' -Message 'Imported records should remain distinguishable from the official source'
    Assert-Equal -Actual $script:UserImportRecords[0].GwpStandard -Expected 'EN 15804+A2' -Message 'Imported GWP standard should persist'
    Assert-Equal -Actual $script:UserImportRecords[0].SolarReflectance.Value -Expected 45.2 -Message 'Solar-reflectance provenance should persist'
    $itemView = Get-ItemView -Record $script:UserImportRecords[0]
    Assert-Equal -Actual $itemView.SourceUrl -Expected 'https://example.org/epd' -Message 'The source URL should remain attached to the imported record'
    Assert-Equal -Actual $itemView.LicenseStatus -Expected $script:UserImportLicenseStatus -Message 'The API should disclose that rights are user-attested, not independently verified'
    Assert-Equal -Actual (Test-Path -LiteralPath $script:UserImportStoreFile) -Expected $true -Message 'Confirmed imports should be stored locally'

    $duplicate = New-UserImportPreview -CsvText $validCsv
    Assert-Equal -Actual $duplicate.validRowCount -Expected 0 -Message 'An unchanged source ID/version should not be imported twice'
    Assert-Equal -Actual $duplicate.duplicateRowCount -Expected 1 -Message 'Unchanged duplicates should be reported as skipped'

    $conflictingCsv = $validCsv.Replace(',25.5,EN 15804+A2,', ',26.5,EN 15804+A2,')
    $conflict = New-UserImportPreview -CsvText $conflictingCsv
    Assert-Equal -Actual $conflict.validRowCount -Expected 0 -Message 'Conflicting content for an existing source ID/version must be blocked'
    Assert-Equal -Actual $conflict.errorRowCount -Expected 1 -Message 'Conflicts should be surfaced as row errors'

    $script:UserImportStateLoaded = $false
    $script:UserImportRecords = @()
    $script:UserImportBatches = @()
    Ensure-UserImportState
    Assert-Equal -Actual $script:UserImportRecords.Count -Expected 1 -Message 'Stored imports should reload after an app restart'
    $script:Dataset = @()
    $script:CatalogIndex = @()
    $script:CombinedCatalogIndex = $null
    $catalog = Get-SearchableCatalog
    $search = Find-MaterialRecords -Records $catalog.Records -Index $catalog.Index -Query 'Pine panel'
    Assert-Equal -Actual $search.Records.Count -Expected 1 -Message 'Imported material names should be searchable'
    Assert-Equal -Actual $search.Records[0].RecordKind -Expected 'user-import' -Message 'Search results should preserve local-import provenance'
    Assert-Equal -Actual (Get-SourceProvenance).userImportRecordCount -Expected 1 -Message 'The API provenance should report local imported records'

    $ownerIndex = Build-MaterialCatalogIndex -Records @(
        [pscustomobject]@{ Name = 'Brick'; Category = 'Masonry'; Owner = 'Wienerberger GmbH' },
        [pscustomobject]@{ Name = 'Floor finish'; Category = 'Flooring'; Owner = 'Charon AG' },
        [pscustomobject]@{ Name = 'Insulation'; Category = 'Thermal'; Owner = 'ROCKWOOL' }
    )
    Assert-Equal -Actual (Find-MaterialRecords -Records @(
        [pscustomobject]@{ Name = 'Brick'; Category = 'Masonry'; Owner = 'Wienerberger GmbH' },
        [pscustomobject]@{ Name = 'Floor finish'; Category = 'Flooring'; Owner = 'Charon AG' },
        [pscustomobject]@{ Name = 'Insulation'; Category = 'Thermal'; Owner = 'ROCKWOOL' }
    ) -Index $ownerIndex -Query 'Wienerberger').Records.Count -Expected 1 -Message 'Exact manufacturer-owner searches should find matching catalog entries'
    Assert-Equal -Actual (Find-MaterialRecords -Records @(
        [pscustomobject]@{ Name = 'Brick'; Category = 'Masonry'; Owner = 'Wienerberger GmbH' },
        [pscustomobject]@{ Name = 'Floor finish'; Category = 'Flooring'; Owner = 'Charon AG' },
        [pscustomobject]@{ Name = 'Insulation'; Category = 'Thermal'; Owner = 'ROCKWOOL' }
    ) -Index $ownerIndex -Query 'Haro').Records.Count -Expected 0 -Message 'A brand query must not match a substring inside an unrelated owner or product'
    Assert-Equal -Actual (Find-MaterialRecords -Records @(
        [pscustomobject]@{ Name = 'Brick'; Category = 'Masonry'; Owner = 'Wienerberger GmbH' },
        [pscustomobject]@{ Name = 'Floor finish'; Category = 'Flooring'; Owner = 'Charon AG' },
        [pscustomobject]@{ Name = 'Insulation'; Category = 'Thermal'; Owner = 'ROCKWOOL' }
    ) -Index $ownerIndex -Query 'Rockwoll').Records.Count -Expected 0 -Message 'Unverified manufacturer misspellings must not be silently aliased'
    Assert-Equal -Actual @(Get-MaterialQueryTerms -Query 'Holz Reinlein').Count -Expected 1 -Message 'Manufacturer searches must not expand into generic material aliases'

    Assert-Equal -Actual (Remove-UserImportBatch -BatchId $imported.batchId) -Expected $true -Message 'A user should be able to remove a local import batch'
    Assert-Equal -Actual $script:UserImportRecords.Count -Expected 0 -Message 'Removed batch records must leave the searchable catalog'
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}

Write-Output 'Local catalog import tests passed.'
