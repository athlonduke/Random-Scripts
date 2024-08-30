# taken from https://www.thewindowsclub.com/find-chkdsk-results-in-event-viewer-logs

get-winevent -FilterHashTable @{logname="Application"; id="1001"}| ?{$_.providername –match "wininit"} | fl timecreated, message
