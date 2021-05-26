# logging framework - lets use windows event(s) - check to see if it exists or not else create it
if ([System.Diagnostics.EventLog]::SourceExists("ps_syncNew") -eq $False) {
  New-EventLog -LogName 'pcloud_rclone' -Source 'ps_syncNew'
}

Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 1 -Message "Starting ps_syncNew via rclone and powershell"
# read last run
$lastrun = Get-Content -Path "P:\scripts\lastrun.txt"
Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 2 -Message "Last run ts from lastrun.txt $($lastrun)"


$localmd5 = Import-CSV -Path "P:\scripts\localfull.csv" | Select-Object -ExpandProperty MD5
Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 3 -Message  "Stored local md5's in variable"

Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 4 -Message  "Checking Rclone for new files"
rclone md5sum remote: --dry-run --max-age "$lastrun" --filter-from "P:\scripts\filter-file.txt" 2>&1 | % ToString -OutVariable remoteFiles
# identify errors when no checksum exists, we also need to remove them from the remountfiles var otherwise our counts are wrong.
# TODO how to handle the errors since lastrun will not recheck them next run...
Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 4 -Message  "Finding errors in sum'ing"
$remotesumerrors = $remoteFiles | Select-String  -Pattern '^[a-f0-9]{32}(  )' -NotMatch
Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 4 -Message  "found $($remotesumerrors.Matches.Count) paths without checksums"
$remotesumerrors | Out-File "P:\scripts\sumerrors.txt" -Append
$remoteFiles = $remoteFiles | Select-String  -Pattern '^[a-f0-9]{32}(  )'
$remoteCount = $remotefiles | Measure-Object -Line | Select-Object -expand Lines
Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 123 -Message "Found $($remoteCount) remote file(s)"
Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 5 -Message  "Getting rclone md5's"
$remotefilehash = $remotefiles -replace '^[a-f0-9]{32}(  )', '$0=  ' | ConvertFrom-StringData
$remotemd5 = $remotefiles.foreach( { ($_ -split '\s+')[0] })
Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 6 -Message  "checking for diffs..."
$diffmd5 = (Compare-Object -ReferenceObject $localmd5 -DifferenceObject $remotefilehash | Where-Object { ($_.SideIndicator -eq '=>') } |  Select-Object -ExpandProperty InputObject)
$diffCount = $diffmd5 | Measure-Object -Line | Select-Object -expand Lines
Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 123 -Message "Found $($diffCount) file(s) that need to be copied"
#write the file details to a rclone includes file
Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 7 -Message  "write file path details to a rclone includes file"
$diffmd5.values | Out-File "P:\scripts\includeFile.txt"

foreach ($path in $diffmd5.values) {
  rclone copy remote:"$path" "C:\Users\Tony\Pictures" --no-traverse
  Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 666 -Message  "copying file path: $($path)"
}

$localfiles = Get-ChildItem "C:\Users\Tony\Pictures" -Recurse -File | Where-Object { $_.LastWriteTime -gt $lastrun } | select-object name, fullname, @{Name = "MD5"; Expression = { (Get-FileHash $_.FullName -Algorithm MD5).Hash } }
$localCount = $localfiles | Measure-Object | Select-Object -expand Count

if ( $localCount -ge $diffCount ) {
  Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 555 -Message "All files copied to local - updating CSV"
  $localfiles | Export-Csv "P:\scripts\localfull.csv" -NoTypeInformation -Append
  Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 8 -Message  "write the current date script was run minus 1 day for posterierity"
  Get-Date (Get-Date).AddDays(-1) -format "yyyy-MM-dd" | Out-File "P:\scripts\lastrun.txt"
  Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 9 -Message  "Completed"
}
else {
  $localfiles | Export-Csv "P:\scripts\localfull.csv" -NoTypeInformation -Append
  Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 99 -Message  "Local files do not match expected count! - not everything was copied, will not update lastrun dttm."
  Write-EventLog -log pcloud_rclone -source ps_syncNew -EntryType Information -eventID 9 -Message  "Completed - but not all files were counted - will leave settings for next run"    
}

Clear-Content "P:\scripts\includeFile.txt"