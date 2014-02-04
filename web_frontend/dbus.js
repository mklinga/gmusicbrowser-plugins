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
	if(xmlHttpRequst !== false)
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
		};
		xmlHttpRequst.send('data=' + JSON.stringify(data));
	}
	else {
		console.error("Please use browser with Ajax support.!");
	}
}

function run(command) {
	doAjaxMagic({cmd: 'run_command', data: command }, function(data) {
		console.log(JSON.parse(data));
	});
}

function runCommandBox() {
	var command = document.getElementById("commandbox").value;
	run(command);
	document.getElementById("commandbox").value = "";
}

function getSongInfo() {
	doAjaxMagic(({cmd: 'getplaying_data', data: ''}), function(data) {
		console.log(data);
		var songData = JSON.parse(data);
		document.getElementById("header").innerHTML = "";
	});
}

function serverSideEvent() {
	if(typeof(EventSource)!=="undefined") {
		var source=new EventSource("backend.php");
		source.onmessage=function(event) {
			console.log(event.data);
			document.getElementById("header").innerHTML = event.data;
		};
	}
	else {
		document.getElementById("result").innerHTML="Sorry, your browser does not support server-sent events...";
	}
}

window.onload = function() {
	serverSideEvent();
	// console.log("Getting song information...");
	// getSongInfo();
};
