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

	<button onclick="run('PrevSong');">Previous song</button>
	<button onclick="run('PlayPause');">Play/pause</button>
	<button onclick="run('NextSong');">Next song</button><br/>

	<p>
	Run any gmusicbrowser command<br/>
	<input id="commandbox" placeholder="run command" /><button onclick="runCommandBox();">Run</button>
	</p>
	<button onclick="run('PLUGIN_ALBUMRANDOM3_GetNewAlbum');">Albumrandom3: Get new album</button><br/>

	<span id="result"></span>
	</body>
</html>
