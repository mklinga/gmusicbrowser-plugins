<!DOCTYPE html>
<html>
	<head>
		<meta http-equiv="content-type" content="text/html; charset=utf-8" />
		<title>Title</title>
	</head>
	<body>
	<h2>Now Playing</h2>
	<h1 id="header"><h1>
	<button onclick="doAjaxMagic('PlayPause', function(data) { console.log(JSON.parse(data)); });">Play/pause</button>
	<span id="result"></span>

	<script>
function doAjaxMagic(data, success)
{
	var url = "backend.php";
	var method = 'POST';
	var async = true;
	var xmlHttpRequst = false;
 
    if (window.XMLHttpRequest) {
        xmlHttpRequst = new XMLHttpRequest();
    }
 
	// If AJAX supported
	if(xmlHttpRequst != false)
	{
		// Open Http Request connection
		xmlHttpRequst.open(method, url, async);
		// Set request header (optional if GET method is used)
		xmlHttpRequst.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
		// Callback when ReadyState is changed.
		xmlHttpRequst.onreadystatechange = function()
		{
			if (xmlHttpRequst.readyState == 4) {
				success(xmlHttpRequst.responseText);
			}
		}
		xmlHttpRequst.send('data=' + data);
	}
	else {
		console.error("Please use browser with Ajax support.!");
	}
}

window.onload = function() {
	console.log("Getting song information...");
	doAjaxMagic('', function(data) {
		document.getElementById("header").innerHTML = JSON.parse(data);
	});
}
	</script>
	</body>
</html>
