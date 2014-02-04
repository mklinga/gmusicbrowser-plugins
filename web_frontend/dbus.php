<!DOCTYPE html>
<html>
	<head>
		<meta http-equiv="content-type" content="text/html; charset=utf-8" />
		<script type="text/javascript" src="dbus.js"></script>
		<link rel='stylesheet' href='style.css' type='text/css' media='all' />
		<title>Title</title>
	</head>
	<body>
	<h2>Now Playing</h2>
	<h1 id="header"></h1>

	<button class="playbutton" onclick="run('PrevSong');">Previous song</button>
	<button class="playbutton" onclick="run('PlayPause');">Play/pause</button>
	<button class="playbutton" onclick="run('NextSong');">Next song</button><br/>

	<p>
	Run any gmusicbrowser command<br/>
	<form action="#" onsubmit="runCommandBox();"><input id="commandbox" placeholder="run command" /><button type="submit">Run</button></form>
	</p>
	<button onclick="run('PLUGIN_ALBUMRANDOM3_GetNewAlbum');"><span>Get new album</span><br/><span class="pluginname">(Albumrandom3)</span></button><br/>
	<a href="#" onclick="getSongInfo();">Dump song information to console</a><br/>
	<span id="result"></span>
	</body>
</html>
