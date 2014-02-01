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
	if ($_POST['data'] == "PlayPause") {
		$DBusProxy->RunCommand("PlayPause");
		$result = "Play/Pause <- done";
	}
	else
		$result = $songInfo['artist'] . " - " . $songInfo['title'] . " <br/>";
}
echo json_encode($result);


?>

