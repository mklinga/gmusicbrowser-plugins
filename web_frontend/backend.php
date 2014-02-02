<?php
 
$DBus = new Dbus( Dbus::BUS_SESSION );
 
$DBusProxy = $DBus->createProxy
    (
        "org.gmusicbrowser", // connection name
        "/org/gmusicbrowser", // object
        "org.gmusicbrowser" // interface
    );
 
$songInfo = $DBusProxy->CurrentSong()->getData();

$result = "No (proper) data recieved!";

if (isset($_POST['data'])) {
	$data = json_decode($_POST['data']);

	if ($data->cmd == "getplaying_data")
		$result = $songInfo['artist'] . " - " . $songInfo['title'] . " <br/>";
	else if ($data->cmd == "run_command") {
		$result = $DBusProxy->RunCommand($data->data);
	}
}
echo json_encode($result);


?>

