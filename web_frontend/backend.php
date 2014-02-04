<?php
 
$DBus = new Dbus( Dbus::BUS_SESSION );
 
$DBusProxy = $DBus->createProxy
    (
        "org.gmusicbrowser", // connection name
        "/org/gmusicbrowser", // object
        "org.gmusicbrowser" // interface
    );

$result = "No (proper) data recieved!";

if (isset($_POST['data'])) {
	$data = json_decode($_POST['data']);

	if ($data->cmd == "getplaying_data") {
		$result = $DBusProxy->CurrentSong()->getData();
	}
	else if ($data->cmd == "run_command") {
		$result = $DBusProxy->RunCommand($data->data);
	}

	echo json_encode($result);
}
else {
	/* server-sent event */
	header('Content-Type: text/event-stream');
	header('Cache-Control: no-cache');

	$songInfo = $DBusProxy->CurrentSong()->getData();
	echo "data: " . $songInfo['artist'] . " - " . $songInfo['title'] . " \n\n";
	flush();
}


?>

