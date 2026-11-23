# TGFR Word exam-copy helpers. Windows PowerShell 5.1 / .NET Framework.
# The source document is never edited. Completed exam copies are not rollback data.
# Microsoft documents w:noProof as "Do Not Check Spelling or Grammar":
# https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.noproof
# https://learn.microsoft.com/en-us/office/vba/api/word.range.noproofing
# This is document formatting, not a policy preventing a user changing formatting,
# pasting text with different formatting, using an add-in, or opening another file.

function Initialize-TgfrWordZip {
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
}

function Get-TgfrWordNamespaces {
    return @('http://schemas.openxmlformats.org/wordprocessingml/2006/main',
             'http://purl.oclc.org/ooxml/wordprocessingml/main')
}

function Read-TgfrZipXml {
    param($Archive, [string]$Name)
    $entry = $Archive.GetEntry($Name)
    if ($null -eq $entry) { throw "Required document part is missing: $Name" }
    if ($entry.Length -gt 33554432) { throw "XML part is too large (32 MiB maximum): $Name" }
    $inputStream = $entry.Open()
    $memory = New-Object System.IO.MemoryStream
    try {
        $buffer = New-Object byte[] 65536
        $total = 0L
        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += $read
            if ($total -gt 33554432) { throw "Expanded XML exceeds its limit: $Name" }
            $memory.Write($buffer, 0, $read)
        }
        $memory.Position = 0
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $settings.MaxCharactersInDocument = 33554432
        $reader = [System.Xml.XmlReader]::Create($memory, $settings)
        try {
            $document = New-Object System.Xml.XmlDocument
            $document.PreserveWhitespace = $true
            $document.XmlResolver = $null
            $document.Load($reader)
            return ,$document
        } finally { $reader.Dispose() }
    } finally {
        $memory.Dispose()
        $inputStream.Dispose()
    }
}

function Write-TgfrZipXml {
    param($Archive, [string]$Name, [System.Xml.XmlDocument]$Document)
    $existing = $Archive.GetEntry($Name)
    if ($null -ne $existing) { $existing.Delete() }
    $entry = $Archive.CreateEntry($Name, [System.IO.Compression.CompressionLevel]::Optimal)
    $stream = $entry.Open()
    try {
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
        $settings.Indent = $false
        $settings.CloseOutput = $false
        $writer = [System.Xml.XmlWriter]::Create($stream, $settings)
        try { $Document.Save($writer) } finally { $writer.Dispose() }
    } finally { $stream.Dispose() }
}

function New-TgfrXmlDocument {
    param([string]$Xml)
    $document = New-Object System.Xml.XmlDocument
    $document.PreserveWhitespace = $true
    $document.XmlResolver = $null
    $document.LoadXml($Xml)
    return ,$document
}

function Get-TgfrXmlNamespaceManager {
    param([System.Xml.XmlDocument]$Document, [string]$Namespace)
    $manager = New-Object System.Xml.XmlNamespaceManager($Document.NameTable)
    $manager.AddNamespace('w', $Namespace)
    return ,$manager
}

function Resolve-TgfrPackageTarget {
    param([string]$BasePart, [string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target) -or $Target.Contains('\')) {
        throw 'The document contains an invalid part relationship.'
    }
    $base = New-Object System.Uri("https://tgfr.invalid/$BasePart")
    $resolved = New-Object System.Uri($base, $Target)
    if ($resolved.Scheme -ne 'https' -or $resolved.Host -ne 'tgfr.invalid' -or
        $resolved.Query -or $resolved.Fragment) {
        throw 'External or malformed document-part relationship is unsupported.'
    }
    return [System.Uri]::UnescapeDataString($resolved.AbsolutePath).TrimStart('/')
}

function Get-TgfrWordPackageInfo {
    param($Archive)
    if ($Archive.Entries.Count -gt 2500) { throw 'Document contains too many ZIP parts (maximum 2,500).' }
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $expanded = 0L
    foreach ($entry in $Archive.Entries) {
        $name = $entry.FullName
        if (-not $names.Add($name)) { throw "Duplicate or ambiguous ZIP part: $name" }
        if ($name.StartsWith('/') -or $name.Contains('\') -or $name.Contains(':') -or
            @($name.Split('/') | Where-Object { $_ -eq '..' -or $_ -eq '.' }).Count -gt 0) {
            throw "Unsafe ZIP part name: $name"
        }
        $expanded += $entry.Length
        if ($expanded -gt 268435456) { throw 'Expanded document exceeds 256 MiB.' }
        if ($name -match '(?i)^_xmlsignatures/' -or
            $name -match '(?i)(^|/)vba[^/]*\.' -or
            $name -match '(?i)(^|/)(activeX|embeddings)/') {
            throw 'Signed documents, macros, ActiveX and embedded documents are unsupported. Use a plain exam DOCX.'
        }
    }

    $types = Read-TgfrZipXml $Archive '[Content_Types].xml'
    if ($types.DocumentElement.LocalName -ne 'Types' -or
        $types.DocumentElement.NamespaceURI -ne 'http://schemas.openxmlformats.org/package/2006/content-types') {
        throw 'Invalid DOCX content types.'
    }
    foreach ($type in $types.DocumentElement.ChildNodes) {
        if ($type -isnot [System.Xml.XmlElement]) { continue }
        if ($type.GetAttribute('ContentType') -match '(?i)macroenabled|vbaProject|digital-signature|activeX|oleObject') {
            throw 'Signed, macro-enabled or embedded executable document content is unsupported.'
        }
    }
    $rootRels = Read-TgfrZipXml $Archive '_rels/.rels'
    $mainLinks = @($rootRels.DocumentElement.ChildNodes | Where-Object {
        $_ -is [System.Xml.XmlElement] -and $_.GetAttribute('Type') -match '/officeDocument$'
    })
    if ($mainLinks.Count -ne 1 -or $mainLinks[0].GetAttribute('TargetMode') -eq 'External') {
        throw 'The DOCX must contain exactly one internal main-document relationship.'
    }
    $mainPath = Resolve-TgfrPackageTarget '' $mainLinks[0].GetAttribute('Target')
    if ($mainPath -cne 'word/document.xml') {
        throw 'Nonstandard main-document locations are unsupported. Save the source as a normal Word DOCX first.'
    }
    $mainType = @($types.DocumentElement.ChildNodes | Where-Object {
        $_ -is [System.Xml.XmlElement] -and $_.LocalName -eq 'Override' -and
        $_.GetAttribute('PartName') -ceq '/word/document.xml'
    })
    if ($mainType.Count -ne 1 -or $mainType[0].GetAttribute('ContentType') -cne
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml') {
        throw 'Only ordinary Word DOCX documents are supported; templates and macro documents are excluded.'
    }
    $main = Read-TgfrZipXml $Archive $mainPath
    $namespace = $main.DocumentElement.NamespaceURI
    if ((Get-TgfrWordNamespaces) -notcontains $namespace -or $main.DocumentElement.LocalName -ne 'document') {
        throw 'The main part is not recognised WordprocessingML.'
    }
    $relationshipsBase = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    if ($namespace -eq 'http://purl.oclc.org/ooxml/wordprocessingml/main') {
        $relationshipsBase = 'http://purl.oclc.org/ooxml/officeDocument/relationships'
    }
    $relsPath = 'word/_rels/document.xml.rels'
    if ($null -eq $Archive.GetEntry($relsPath)) {
        $rels = New-TgfrXmlDocument '<?xml version="1.0" encoding="utf-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>'
    } else { $rels = Read-TgfrZipXml $Archive $relsPath }
    $styleLinks = @($rels.DocumentElement.ChildNodes | Where-Object {
        $_ -is [System.Xml.XmlElement] -and $_.GetAttribute('Type') -match '/styles$'
    })
    if ($styleLinks.Count -gt 1) { throw 'Multiple styles parts are unsupported.' }
    $stylesPath = 'word/styles.xml'
    if ($styleLinks.Count -eq 1) {
        if ($styleLinks[0].GetAttribute('TargetMode') -eq 'External') { throw 'External styles are unsupported.' }
        $stylesPath = Resolve-TgfrPackageTarget $mainPath $styleLinks[0].GetAttribute('Target')
        if (-not $stylesPath.StartsWith('word/', [System.StringComparison]::Ordinal) -or
            $null -eq $Archive.GetEntry($stylesPath)) { throw 'Styles part is missing or outside the supported Word folder.' }
    } elseif ($null -ne $Archive.GetEntry($stylesPath)) {
        throw 'The source has an unreferenced styles.xml part. Resave it in Word first.'
    }

    # All Word XML is checked before any edits. No Office application or macros run.
    foreach ($entry in $Archive.Entries) {
        if (-not $entry.FullName.StartsWith('word/', [System.StringComparison]::Ordinal) -or
            -not $entry.FullName.EndsWith('.xml', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $part = Read-TgfrZipXml $Archive $entry.FullName
        foreach ($wordNamespace in (Get-TgfrWordNamespaces)) {
            $manager = Get-TgfrXmlNamespaceManager $part $wordNamespace
            if ($part.SelectNodes('//w:documentProtection | //w:writeProtection', $manager).Count -gt 0) {
                throw 'Protected or write-protected documents are unsupported. Prepare an authorised unprotected copy first.'
            }
            if ($part.SelectNodes('//w:altChunk', $manager).Count -gt 0) {
                throw 'Imported altChunk content is unsupported. Open and save a normal DOCX in Word first.'
            }
        }
        # Chart/SmartArt/WordArt DrawingML text cannot be marked with Word w:noProof.
        $unsupported = $part.SelectNodes('//*[local-name()="t" and (namespace-uri()="http://schemas.openxmlformats.org/drawingml/2006/main" or namespace-uri()="http://purl.oclc.org/ooxml/drawingml/main")]')
        foreach ($text in $unsupported) {
            if (-not [string]::IsNullOrWhiteSpace($text.InnerText)) {
                throw 'DrawingML chart, SmartArt or WordArt text is unsupported. Use ordinary Word text/text boxes in the exam copy.'
            }
        }
    }
    return @{ Namespace=$namespace; StylesPath=$stylesPath; HasStyles=($styleLinks.Count -eq 1);
              Relationships=$rels; RelationshipsPath=$relsPath; RelationshipsBase=$relationshipsBase;
              ContentTypes=$types }
}

function Set-TgfrNoProof {
    param([System.Xml.XmlElement]$RunProperties, [string]$Namespace)
    foreach ($child in @($RunProperties.ChildNodes)) {
        if ($child.LocalName -eq 'noProof' -and $child.NamespaceURI -eq $Namespace) {
            [void]$RunProperties.RemoveChild($child)
        }
    }
    $proof = $RunProperties.OwnerDocument.CreateElement('w', 'noProof', $Namespace)
    $value = $RunProperties.OwnerDocument.CreateAttribute('w', 'val', $Namespace)
    $value.Value = 'true'
    [void]$proof.Attributes.Append($value)
    # noProof precedes these members in CT_RPr / CT_RPrBase. Keep rPrChange last.
    $following = @('snapToGrid','vanish','webHidden','color','spacing','w','kern','position',
                   'sz','szCs','highlight','u','effect','bdr','shd','fitText','vertAlign','rtl',
                   'cs','em','lang','eastAsianLayout','specVanish','oMath','rPrChange')
    $before = $null
    foreach ($child in $RunProperties.ChildNodes) {
        if ($child.NamespaceURI -eq $Namespace -and $following -contains $child.LocalName) { $before=$child; break }
    }
    if ($null -eq $before) { [void]$RunProperties.AppendChild($proof) }
    else { [void]$RunProperties.InsertBefore($proof,$before) }
}

function Get-TgfrDirectElement {
    param([System.Xml.XmlNode]$Parent, [string]$LocalName, [string]$Namespace)
    $matches = @($Parent.ChildNodes | Where-Object {
        $_ -is [System.Xml.XmlElement] -and $_.LocalName -eq $LocalName -and $_.NamespaceURI -eq $Namespace
    })
    if ($matches.Count -gt 1) { throw "Duplicate $LocalName element is unsupported." }
    if ($matches.Count -eq 1) { return ,$matches[0] }
    return $null
}

function Set-TgfrWordXmlNoProof {
    param([System.Xml.XmlDocument]$Document)
    foreach ($namespace in (Get-TgfrWordNamespaces)) {
        $manager = Get-TgfrXmlNamespaceManager $Document $namespace
        foreach ($run in @($Document.SelectNodes('//w:r',$manager))) {
            $properties = Get-TgfrDirectElement $run 'rPr' $namespace
            if ($null -eq $properties) {
                $properties=$Document.CreateElement('w','rPr',$namespace)
                [void]$run.PrependChild($properties)
            }
        }
        foreach ($paragraph in @($Document.SelectNodes('//w:p',$manager))) {
            $properties = Get-TgfrDirectElement $paragraph 'pPr' $namespace
            if ($null -eq $properties) {
                $properties=$Document.CreateElement('w','pPr',$namespace)
                [void]$paragraph.PrependChild($properties)
            }
            $mark = Get-TgfrDirectElement $properties 'rPr' $namespace
            if ($null -eq $mark) {
                $mark=$Document.CreateElement('w','rPr',$namespace)
                $before=$null
                foreach ($child in $properties.ChildNodes) {
                    if ($child.NamespaceURI -eq $namespace -and @('sectPr','pPrChange') -contains $child.LocalName) { $before=$child; break }
                }
                if ($null -eq $before) { [void]$properties.AppendChild($mark) }
                else { [void]$properties.InsertBefore($mark,$before) }
            }
        }
        foreach ($style in @($Document.SelectNodes('//w:style',$manager))) {
            $properties = Get-TgfrDirectElement $style 'rPr' $namespace
            if ($null -eq $properties) {
                $properties=$Document.CreateElement('w','rPr',$namespace)
                $before=$null
                foreach ($child in $style.ChildNodes) {
                    if ($child.NamespaceURI -eq $namespace -and @('tblPr','trPr','tcPr','tblStylePr') -contains $child.LocalName) { $before=$child; break }
                }
                if ($null -eq $before) { [void]$style.AppendChild($properties) }
                else { [void]$style.InsertBefore($properties,$before) }
            }
        }
        if ($Document.DocumentElement.LocalName -eq 'styles' -and $Document.DocumentElement.NamespaceURI -eq $namespace) {
            $defaults=Get-TgfrDirectElement $Document.DocumentElement 'docDefaults' $namespace
            if ($null -eq $defaults) {
                $defaults=$Document.CreateElement('w','docDefaults',$namespace)
                [void]$Document.DocumentElement.PrependChild($defaults)
            }
            $runDefaults=Get-TgfrDirectElement $defaults 'rPrDefault' $namespace
            if ($null -eq $runDefaults) {
                $runDefaults=$Document.CreateElement('w','rPrDefault',$namespace)
                [void]$defaults.PrependChild($runDefaults)
            }
            $properties=Get-TgfrDirectElement $runDefaults 'rPr' $namespace
            if ($null -eq $properties) {
                $properties=$Document.CreateElement('w','rPr',$namespace)
                [void]$runDefaults.AppendChild($properties)
            }
        }
        # Covers runs, paragraph marks, style/table overrides and existing historic
        # run properties so rejecting tracked formatting does not restore noProof=false.
        foreach ($properties in @($Document.SelectNodes('//w:rPr',$manager))) {
            Set-TgfrNoProof $properties $namespace
        }
    }
}

function Add-TgfrWordStylesPart {
    param($Archive, $Info)
    if ($Info.HasStyles) { return }
    $styles=New-TgfrXmlDocument ('<?xml version="1.0" encoding="utf-8"?><w:styles xmlns:w="' + $Info.Namespace + '"><w:docDefaults><w:rPrDefault><w:rPr/></w:rPrDefault></w:docDefaults><w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style></w:styles>')
    Write-TgfrZipXml $Archive $Info.StylesPath $styles
    $rels=$Info.Relationships
    $ids=@($rels.DocumentElement.ChildNodes | Where-Object { $_ -is [System.Xml.XmlElement] } | ForEach-Object { $_.GetAttribute('Id') })
    $id='rIdTGFRStyles'
    $suffix=0
    while ($ids -contains $id) { $suffix++; $id='rIdTGFRStyles' + $suffix }
    $relation=$rels.CreateElement('Relationship',$rels.DocumentElement.NamespaceURI)
    $relation.SetAttribute('Id',$id)
    $relation.SetAttribute('Type',($Info.RelationshipsBase + '/styles'))
    $relation.SetAttribute('Target','styles.xml')
    [void]$rels.DocumentElement.AppendChild($relation)
    Write-TgfrZipXml $Archive $Info.RelationshipsPath $rels
    $types=$Info.ContentTypes
    $styleType=$types.CreateElement('Override',$types.DocumentElement.NamespaceURI)
    $styleType.SetAttribute('PartName','/' + $Info.StylesPath)
    $styleType.SetAttribute('ContentType','application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml')
    [void]$types.DocumentElement.AppendChild($styleType)
    Write-TgfrZipXml $Archive '[Content_Types].xml' $types
}

function Test-TgfrNoProofElement {
    param([System.Xml.XmlNode]$Parent, [string]$Namespace)
    if ($null -eq $Parent) { return $false }
    $nodes=@($Parent.ChildNodes | Where-Object { $_.LocalName -eq 'noProof' -and $_.NamespaceURI -eq $Namespace })
    if ($nodes.Count -ne 1) { return $false }
    $attribute=$nodes[0].GetAttributeNode('val',$Namespace)
    if ($null -eq $attribute) { return $true }
    return @('true','1','on') -ccontains $attribute.Value
}

function Test-TgfrWordExamCopy {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $stream=$null
    $archive=$null
    try {
        Initialize-TgfrWordZip
        $full=[System.IO.Path]::GetFullPath($Path)
        if ([System.IO.Path]::GetExtension($full) -ine '.docx') { throw 'Only .docx files are supported.' }
        $stream=[System.IO.File]::Open($full,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
        if ($stream.Length -gt 67108864) { throw 'DOCX exceeds 64 MiB.' }
        $archive=New-Object System.IO.Compression.ZipArchive($stream,[System.IO.Compression.ZipArchiveMode]::Read,$false)
        $info=Get-TgfrWordPackageInfo $archive
        if (-not $info.HasStyles) { throw 'No linked styles/defaults part was found.' }
        $runs=0
        $paragraphs=0
        foreach ($entry in $archive.Entries) {
            if (-not $entry.FullName.StartsWith('word/',[System.StringComparison]::Ordinal) -or
                -not $entry.FullName.EndsWith('.xml',[System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $document=Read-TgfrZipXml $archive $entry.FullName
            foreach ($namespace in (Get-TgfrWordNamespaces)) {
                $manager=Get-TgfrXmlNamespaceManager $document $namespace
                foreach ($run in @($document.SelectNodes('//w:r',$manager))) {
                    $runs++
                    if (-not (Test-TgfrNoProofElement (Get-TgfrDirectElement $run 'rPr' $namespace) $namespace)) {
                        throw "Text run is not marked 'Do not check spelling or grammar': $($entry.FullName)"
                    }
                }
                foreach ($paragraph in @($document.SelectNodes('//w:p',$manager))) {
                    $paragraphs++
                    $pPr=Get-TgfrDirectElement $paragraph 'pPr' $namespace
                    $rPr=$null
                    if ($null -ne $pPr) { $rPr=Get-TgfrDirectElement $pPr 'rPr' $namespace }
                    if (-not (Test-TgfrNoProofElement $rPr $namespace)) { throw "Paragraph mark has proofing enabled: $($entry.FullName)" }
                }
                foreach ($style in @($document.SelectNodes('//w:style',$manager))) {
                    if (-not (Test-TgfrNoProofElement (Get-TgfrDirectElement $style 'rPr' $namespace) $namespace)) {
                        throw "A style has proofing enabled: $($entry.FullName)"
                    }
                }
                foreach ($rPr in @($document.SelectNodes('//w:rPr',$manager))) {
                    if (-not (Test-TgfrNoProofElement $rPr $namespace)) { throw "Run properties have proofing enabled: $($entry.FullName)" }
                }
                if ($document.DocumentElement.LocalName -eq 'styles' -and $document.DocumentElement.NamespaceURI -eq $namespace) {
                    $defaults=$document.SelectSingleNode('/w:styles/w:docDefaults/w:rPrDefault/w:rPr',$manager)
                    if (-not (Test-TgfrNoProofElement $defaults $namespace)) { throw "Document defaults have proofing enabled: $($entry.FullName)" }
                }
            }
        }
        if ($paragraphs -lt 1) { throw 'Document contains no ordinary Word paragraphs.' }
        return @{Ok=$true; Details="Verified NoProof for $runs text runs, $paragraphs paragraph marks, styles and defaults. Applies to this copy; pasted text or changed formatting can override it."; Runs=$runs; Paragraphs=$paragraphs}
    } catch {
        return @{Ok=$false; Details=$_.Exception.Message; Runs=0; Paragraphs=0}
    } finally {
        if ($null -ne $archive) { $archive.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function New-TgfrBlankWordPackage {
    param([System.IO.Stream]$Stream)
    $archive=New-Object System.IO.Compression.ZipArchive($Stream,[System.IO.Compression.ZipArchiveMode]::Create,$true)
    try {
        $parts=[ordered]@{
            '[Content_Types].xml'='<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
            '_rels/.rels'='<?xml version="1.0" encoding="utf-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
            'word/document.xml'='<?xml version="1.0" encoding="utf-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t xml:space="preserve"></w:t></w:r></w:p><w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>'
        }
        foreach ($name in $parts.Keys) {
            $entry=$archive.CreateEntry($name,[System.IO.Compression.CompressionLevel]::Optimal)
            $output=$entry.Open()
            try {
                $bytes=[System.Text.Encoding]::UTF8.GetBytes($parts[$name])
                $output.Write($bytes,0,$bytes.Length)
            } finally { $output.Dispose() }
        }
    } finally { $archive.Dispose() }
}

function New-TgfrWordExamCopy {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$SourcePath='',
          [Parameter(Mandatory=$true)][string]$DestinationPath)
    Initialize-TgfrWordZip
    $destination=[System.IO.Path]::GetFullPath($DestinationPath)
    if ([System.IO.Path]::GetExtension($destination) -ine '.docx') { throw 'The output must use the .docx extension.' }
    if ([System.IO.File]::Exists($destination) -or [System.IO.Directory]::Exists($destination)) {
        throw 'The output already exists. Choose a new filename; existing work is never overwritten.'
    }
    $directory=[System.IO.Path]::GetDirectoryName($destination)
    if (-not [System.IO.Directory]::Exists($directory)) { throw 'The output folder does not exist.' }
    $source=$null
    if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
        $source=[System.IO.Path]::GetFullPath($SourcePath)
        if ([System.IO.Path]::GetExtension($source) -ine '.docx') { throw 'Use an ordinary .docx source. DOC, DOCM and templates are unsupported.' }
        if ([string]::Equals($source,$destination,[System.StringComparison]::OrdinalIgnoreCase)) { throw 'Source and output must be different files.' }
    }
    $temporary=Join-Path $directory ('.tgfr-word-' + [guid]::NewGuid().ToString('N') + '.docx')
    $temporaryStream=$null
    try {
        $temporaryStream=[System.IO.File]::Open($temporary,[System.IO.FileMode]::CreateNew,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
        if ($null -ne $source) {
            $inputStream=[System.IO.File]::Open($source,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
            try {
                if ($inputStream.Length -gt 67108864) { throw 'Source DOCX exceeds 64 MiB.' }
                $inputStream.CopyTo($temporaryStream)
            } finally { $inputStream.Dispose() }
        } else { New-TgfrBlankWordPackage $temporaryStream }
        $temporaryStream.Flush($true)
        $temporaryStream.Dispose()
        $temporaryStream=$null
        $archive=[System.IO.Compression.ZipFile]::Open($temporary,[System.IO.Compression.ZipArchiveMode]::Update)
        try {
            $info=Get-TgfrWordPackageInfo $archive
            Add-TgfrWordStylesPart $archive $info
            $partNames=@($archive.Entries | Where-Object {
                $_.FullName.StartsWith('word/',[System.StringComparison]::Ordinal) -and
                $_.FullName.EndsWith('.xml',[System.StringComparison]::OrdinalIgnoreCase)
            } | ForEach-Object { $_.FullName })
            foreach ($name in $partNames) {
                $document=Read-TgfrZipXml $archive $name
                Set-TgfrWordXmlNoProof $document
                Write-TgfrZipXml $archive $name $document
            }
        } finally { $archive.Dispose() }
        $verified=Test-TgfrWordExamCopy -Path $temporary
        if (-not $verified.Ok) { throw "The prepared exam copy did not verify: $($verified.Details)" }
        # Same-directory File.Move atomically publishes the complete copy and fails
        # if the destination was created meanwhile. It never replaces another file.
        [System.IO.File]::Move($temporary,$destination)
        return @{Path=$destination; Runs=$verified.Runs; Paragraphs=$verified.Paragraphs; Verified=$true;
                 Details=$verified.Details}
    } catch {
        throw "Cannot prepare Word exam copy: $($_.Exception.Message)"
    } finally {
        if ($null -ne $temporaryStream) { $temporaryStream.Dispose() }
        if ([System.IO.File]::Exists($temporary)) { [System.IO.File]::Delete($temporary) }
    }
}
