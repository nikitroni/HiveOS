param(
  [Parameter(Mandatory = $true)]
  [string]$jarPath,
  [Parameter(Mandatory = $true)]
  [string]$outputPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$resolvedJar = (Resolve-Path -LiteralPath $jarPath).Path
$recipeTypes = @(
  'productivebees:bee_breeding',
  'productivebees:bee_conversion',
  'productivebees:bee_spawning',
  'productivebees:bee_fishing'
)

function Test-BeeEggNode($node) {
  if ($null -eq $node) {
    return $false
  }
  if ($node -is [System.Array]) {
    foreach ($item in $node) {
      if (Test-BeeEggNode $item) {
        return $true
      }
    }
    return $false
  }
  if ($node -isnot [pscustomobject]) {
    return $false
  }
  foreach ($property in $node.PSObject.Properties) {
    if ($property.Name -in @('item', 'id', 'items') -and
        $property.Value -eq 'productivebees:spawn_egg_configurable_bee') {
      return $true
    }
    if (Test-BeeEggNode $property.Value) {
      return $true
    }
  }
  return $false
}

function Test-BeeEggOutput($recipe) {
  foreach ($property in $recipe.PSObject.Properties) {
    if ($property.Name -match '^(output|outputs|outputItems|result|results|recipeOutput)$' -and
        (Test-BeeEggNode $property.Value)) {
      return $true
    }
  }
  return $false
}
$recipes = [System.Collections.Generic.List[object]]::new()
$species = [System.Collections.Generic.List[object]]::new()
$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedJar)

try {
  foreach ($entry in $archive.Entries) {
    if ($entry.FullName -notmatch '^data/[^/]+/(recipe|productivebees)/.+\.json$') {
      continue
    }
    $reader = [System.IO.StreamReader]::new($entry.Open())
    try {
      $data = $reader.ReadToEnd() | ConvertFrom-Json
    } finally {
      $reader.Dispose()
    }
    if ($entry.FullName -match '^data/[^/]+/recipe/' -and
        ($recipeTypes -contains [string]$data.type -or (Test-BeeEggOutput $data))) {
      $recipes.Add([ordered]@{
        path = $entry.FullName
        data = $data
      })
    } elseif ($entry.FullName -match '^data/productivebees/productivebees/') {
      $species.Add([ordered]@{
        path = $entry.FullName
        id = 'productivebees:' + [System.IO.Path]::GetFileNameWithoutExtension($entry.Name)
        data = $data
      })
    }
  }
} finally {
  $archive.Dispose()
}

$catalog = [ordered]@{
  format = 'hiveos.bee-recipes.v1'
  sourceJar = [System.IO.Path]::GetFileName($resolvedJar)
  sourceSha256 = (Get-FileHash -LiteralPath $resolvedJar -Algorithm SHA256).Hash.ToLowerInvariant()
  scope = 'unfiltered mod JAR candidates; loaded datapacks may override or remove entries'
  recipes = @($recipes | Sort-Object { $_.path })
  species = @($species | Sort-Object { $_.id }, { $_.path })
}

$json = ConvertTo-Json -InputObject $catalog -Depth 100
$parent = Split-Path -Parent $outputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) {
  New-Item -ItemType Directory -Path $parent | Out-Null
}
[System.IO.File]::WriteAllText((Join-Path (Get-Location).Path $outputPath), $json + "`n",
  [System.Text.UTF8Encoding]::new($false))
Write-Output ("Extracted {0} creation paths and {1} species definitions" -f
  $recipes.Count, $species.Count)
