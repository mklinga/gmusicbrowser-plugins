# Gmusicbrowser: Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
# Sunshine: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
# Sunshine icons are made by Daily Overview (http://www.dailyoverview.com/)
#
# This file is a plugin to Gmusicbrowser.
# It is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

# TODO:
#
# BUGS:
#

=gmbplugin SUNSHINE
name	Sunshine
title	Sunshine 2.0
desc	For scheduling pleasant nights and sharp-starting mornings
=cut

package GMB::Plugin::SUNSHINE;
my $VNUM = '2.0';

use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_SUNSHINE2_',
};

use Gtk2::Notify -init, ::PROGRAM_NAME;

::SetDefaultOptions(OPT, ShowNotifications => 0, ShowButton => 1, SleepEnabled => 1, WakeEnabled => 1,
	 A_SleepCommandBox => 'Play/Pause', A_WakeCommandBox => 'Play/Pause', Advanced_VolumeFadeInPerc => 100);

my %dayvalues= ( Mon => 1, Tue => 2,Wed => 3,Thu => 4,Fri => 5,Sat => 6,Sun => 0);
my @daynames = ('Sun','Mon','Tue','Wed','Thu','Fri','Sat' );

my %sunshine_button=
(	class	=> 'Layout::Button',
	stock	=> 'plugin-sunshine',
	tip	=> " Sunshine v".$VNUM." \n LClick - Launch enabled Alarmmodes \n MClick - Force-launch Sleepmode \n RClick - Force-launch Wakemode",
	click1 => sub {LaunchSunshine();},
	click2 => sub {LaunchSunshine(force => 'Sleep');},
	click3 => sub {LaunchSunshine(force => 'Wake');},
	autoadd_type	=> 'button main',
);

my %SleepSchemes=
(
	default1 => {type => 'Sleep',label => 'The End', sleepmode => 'simpletime', simpletime => 30, simplecount => 8, launchautomatically => 1, 
		launchautomaticallyhour => 22, launchautomaticallymin => 0, svolumefadecheck => 1, svolumefadefrom => -1,	svolumefadeto => 20, schemekey => 'default1'},
	default2 => {type => 'Sleep',label => 'Take It As It Comes', sleepmode => 'queue', ignorelast => 0,	svolumefadecheck => 1, svolumefadefrom => 100,
		svolumefadeto => 0, launchautomaticallyhour => 22, launchautomaticallymin => 0, simplecount => 8, simpletime => 30, schemekey => 'default2'},
	default3 => {type => 'Sleep',label => 'When The Music\'s Over', sleepmode => 'albumchange', svolumefadecheck => 0, simplecount => 8, 
		simpletime => 30, launchautomaticallyhour => 22,launchautomaticallymin => 0, svolumefadefrom => 50, svolumefadeto => 50, schemekey => 'default3'},
	default4 => {type => 'Sleep',label => 'Easy Ride', sleepmode => 'simplecount', svolumefadecheck => 1, svolumefadefrom => -1, launchautomaticallyhour => 22, 
		launchautomaticallymin => 0, svolumefadeto => 30, simplecount => 8, simpletime => 30, schemekey => 'default4'}
);
my %WakeSchemes=
(
	default1 => {type => 'Wake',label => 'Strange Days', wvolumefadecheck => 1, wvolumefadefrom => 0, wvolumefadeto => 100, wakefadeinmin => 60, schemekey => 'default1',
		wakelaunchhour => 3, wakelaunchmin => 30, wakecustomtimes => 1, wakecustomtimestrings => ['Sat10:00','Sun10:00'], wakerepeatcheck => 1, wakestartfromcombo => 'First Track'},
	default2 => {type => 'Wake',label => 'Celebration Of The Lizard', wakelaunchhour => 3, wakelaunchmin => 30, wakefadeinmin => 30, 
		wakestartfromcombo => 'First Track', wvolumefadefrom => 50, wvolumefadeto => 50, schemekey => 'default2'},
	default3 => {type => 'Wake',label => 'Waiting For The Sun', wakecustomtimes => 1, wvolumefadefrom => 50, wvolumefadeto => 50,wakelaunchhour => 3, wakelaunchmin => 30, 
		wakecustomtimestrings => ['Mon:6:0','Tue:6:0','Wed:6:0','Thu:6:0','Fri:6:0'], wakefadeinmin => 30, wakerepeatcheck => 1, wakestartfromcombo => 'First Track', schemekey => 'default3'}
);

my %SleepModes= 
(
	# Available Variables:
	# all values as $Alarm{value}
	# EXTRAS for 'value': $passedtime (in seconds), $passedtracks, $initialalbum
	# (lengthcalc doesn't take current song in count, do that in function)
	queue => {label => 'When queue is empty', CalcLength => 'my $l=0; $l += Songs::Get($_,qw/length/) for (@$::Queue); return $l;', 
		IsCompleted => 'return !scalar@$::Queue;'}, 
	simpletime => {label => 'When time has passed', CalcLength => 'return 60*$Alarm{simpletime}', 
		IsCompleted => 'return ($Alarm{passedtime} > 60*($Alarm{simpletime} || 30))'}, 
	simplecount => {label => 'When amount of songs is played',
		CalcLength => 'my @IDs = ::GetNextSongs($Alarm{simplecount}); splice (@IDs, 0,1);my $l=0;$l += Songs::Get($_,qw/length/) for (@IDs);return $l;', 
		IsCompleted => 'return ($Alarm{passedtracks} >= ($Alarm{simplecount} || 5))'},
	immediate => {label => 'Sleep immediately', CalcLength => 'return 0', IsCompleted => 'return 1;'},
	albumchange => {label => 'When currently playing album is played', 
		CalcLength => 'my $l=0;	my $IDs = AA::GetIDs(qw/album/,Songs::Get_gid($::SongID,qw/album/));Songs::SortList($IDs,$::Options{Sort});splice (@$IDs, 0, Songs::Get($::SongID,qw/track/));$l += Songs::Get($_,qw/length/) for (@$IDs); return $l;',
		IsCompleted => 'return ($Alarm{initialalbum} ne (join " ",Songs::Get($::SongID,qw/album_artist album/)))'},
);

my %prefWidgets=
(
	sleepbutton_new => {type => 'IconButton', mode => 'SleepTopButton', pic => 'gtk-add', action => 'New'},
	sleepbutton_rename => {type => 'IconButton', mode => 'SleepTopButton', pic => 'gtk-edit', action => 'Rename'},
	sleepbutton_remove => {type => 'IconButton', mode => 'SleepTopButton', pic => 'gtk-remove', action => 'Remove'},
	wakebutton_new => {type => 'IconButton', mode => 'WakeTopButton', pic => 'gtk-add', action => 'New'},
	wakebutton_rename => {type => 'IconButton', mode => 'WakeTopButton', pic => 'gtk-edit', action => 'Rename'},
	wakebutton_remove => {type => 'IconButton', mode => 'WakeTopButton', pic => 'gtk-remove', action => 'Remove'},
	
	#sleep-related items
	svolumefadecheck => {type => 'CheckButton', mode => 'Sleep', text => ' Fade volume from', friendwidgets => ['svolumefadefrom','svolumefadeto']},
	svolumefadefrom => { type => 'SpinButton', mode => 'Sleep', adjust => 'Gtk2::Adjustment->new(100,-1,100,1,10,0);', defaultvalue => 50},
	svolumefadeto => { type => 'SpinButton', mode => 'Sleep', adjust => 'Gtk2::Adjustment->new(0,0,100,1,10,0);', defaultvalue => 50},
	scommonlabel1 => { type => 'Label', mode => 'Sleep', text => 'to'},
	scommandcheck => {type => 'CheckButton', mode => 'Sleep', text => ' Run command:', friendwidgets => ['scommandentry']},
	scommandentry => {type => 'Entry', mode => 'Sleep'},
	sleepschemecombo => {type => 'ComboBox', mode => 'Sleep', noupdate => 1},
	sleepmodecombo => {type => 'ComboBox', mode => 'Sleep', noupdate => 1},
	launchautomaticallycheck => {type => 'CheckButton', mode => 'Sleep', text => 'Launch automatically at', friendwidgets => ['launchautomaticallyhour','launchautomaticallymin','sleeprepeatcheck']},
	launchautomaticallyhour => { type => 'SpinButton', mode => 'Sleep', adjust => 'Gtk2::Adjustment->new(0,0,23,1,10,0);', defaultvalue => 22},
	launchautomaticallymin => { type => 'SpinButton', mode => 'Sleep', adjust => 'Gtk2::Adjustment->new(0,0,59,1,10,0);', defaultvalue => 0},
	shutdowngmb => {type => 'CheckButton', mode => 'Sleep', text => 'Shut down gmusicbrowser when finished', friendwidgets => ['shutdowncomputer']},
	shutdowncomputer => {type => 'CheckButton', mode => 'Sleep', text => 'Turn Off Computer', friendcondition => 'return (not defined $::Options{Shutdown_cmd})'},
	sleeplabel1 => { type => 'Label', mode => 'Sleep', text => ' Sleepmode: '},
	sleeplabel2 => { type => 'Label', mode => 'Sleep', text => ' Minutes in timed-mode: '},
	simpletime => { type => 'SpinButton', mode => 'Sleep', adjust => 'Gtk2::Adjustment->new(5,1,720,1,10,0);', defaultvalue => 30},
	simplecount => { type => 'SpinButton', mode => 'Sleep', adjust => 'Gtk2::Adjustment->new(10,1,100,1,10,0);', defaultvalue => 8},
	sleeplabel3 => { type => 'Label', mode => 'Sleep', text => ' Tracks in countmode: '},
	ignorelastinqueue => {type => 'CheckButton', mode => 'Sleep', text => 'Ignore last track in queue-mode'},
	sleepstatuslabel => { type => 'Label', mode => 'Sleep', text => "  Sleepmode:\tNo active sleepmodes"},
	sleeprepeatcheck => {type => 'CheckButton', mode => 'Sleep', text => 'Repeat'},	

	#wake
	wvolumefadecheck => {type => 'CheckButton', mode => 'Wake', text => ' Fade volume from', friendwidgets => ['wvolumefadefrom','wvolumefadeto','wakefadeinmin']},
	wvolumefadefrom => { type => 'SpinButton', mode => 'Wake', adjust => 'Gtk2::Adjustment->new(100,0,100,1,10,0);', defaultvalue => 50},
	wvolumefadeto => { type => 'SpinButton', mode => 'Wake', adjust => 'Gtk2::Adjustment->new(0,0,100,1,10,0);', defaultvalue => 50},
	wakefadeinmin => { type => 'SpinButton', mode => 'Wake', adjust => 'Gtk2::Adjustment->new(1,1,600,1,10,0);', defaultvalue => 30},
	wcommonlabel1 => { type => 'Label', mode => 'Wake', text => 'to'},
	wcommandcheck => {type => 'CheckButton', mode => 'Wake', text => ' Run command:', friendwidgets => ['wcommandentry']},
	wcommandentry => {type => 'Entry', mode => 'Wake'},
	wakeschemecombo => {type => 'ComboBox', mode => 'Wake', noupdate => 1},
	wakelaunchhour => { type => 'SpinButton', mode => 'Wake', adjust => 'Gtk2::Adjustment->new(0,0,23,1,10,0);', defaultvalue => 6, wrap => 1},
	wakelaunchmin => { type => 'SpinButton', mode => 'Wake', adjust => 'Gtk2::Adjustment->new(0,0,59,1,10,0);', defaultvalue => 30, wrap => 1},
	wakestartfromcheck => {type => 'CheckButton', mode => 'Wake', text => 'Start playing from: ', friendwidgets => ['wakestartfromcombo']},
	wakestartfromcombo => {type => 'ComboBox', mode => 'Wake'},
	wakelabel1 => { type => 'Label', mode => 'Wake', text => ' Wake up at: '},
	wakelabel2 => { type => 'Label', mode => 'Wake', text => 'in'},
	wakelabel3 => { type => 'Label', mode => 'Wake', text => 'minutes'},
	wakestatuslabel => { type => 'Label', mode => 'Wake', text => "  Wakemode:\tNo active wakemodes"},
	wakerepeatcheck => {type => 'CheckButton', mode => 'Wake', text => 'Repeat alarm'},
	wakefiltercheck => {type => 'CheckButton', mode => 'Wake', text => 'Select source', friendwidgets => ['wakefilterbutton']},
	wakeplaymodecheck => {type => 'CheckButton', mode => 'Wake', text => 'Select playmode', friendwidgets => ['wakeplaymodebutton']},
	wakeplaymodebutton => {type => 'IconButton', mode => 'Wake', text => 'Select', pic => 'gtk-sort-ascending', func => \&SortMenu},
	wakefilterbutton => {type => 'IconButton', mode => 'Wake', text => 'Select', pic => 'gmb-filter', func => \&FilterMenu},
);

my %SleepWakeCommands=
(
	play => {label => 'Play', command => '::Play'},
	playpause => {label => 'Play/Pause', command => '::PlayPause'},
	pause => {label => 'Pause', command => '::Pause'},
	stop => {label => 'Stop', command => '::Stop'},
	prevsong => {label => 'Prev', command => '::PrevSong'},
	nextsong => {label => 'Next', command => '::NextSong'},
);

my %AdvancedDefaults=
(
	SleepCommand => '::PlayPause',
	WakeCommand => '::PlayPause',
	KeepAlarms => 1,
	MoreNotifications => 0,
	MultipleAlarms => 0,
	Albumrandom => 0,
	IgnoreLastInCount => 0,
	DontFinishLastInTimed => 0,
	ManualTimeSpin => 30,
	ManualFadeTime => 0,
	SkipAlarmIfPlaying => 1,
);

my @StartFromItems = ('First Track', 'Random track');
my @ActiveAlarms=();

#notify-items
my $notify; my $lastlaunch=0; my @notifybuffer; my $notifyhandle;
my ($Daemon_name,$can_actions,$can_body);

my $handle; my $volumehandle;
my $EditingScheme=0;
my $oldID=-1;#prevent double-call to SongChanged
my $createdPrefs = 0;

sub Start
{
	if ($::Options{OPT.'ShowButton'} == 1){Layout::RegisterWidget(Sunshine=>\%sunshine_button);}
	::Watch($handle, PlayingSong => \&SongChanged);
	
	if (!$::Options{OPT.'firstrun'})
	{
		for (keys %WakeSchemes) { $WakeSchemes{$_} = SetDefaultFilterSort($WakeSchemes{$_}); }
		for (keys %AdvancedDefaults) { $::Options{OPT.'Advanced_'.$_} = $AdvancedDefaults{$_}; }
		
		%{$::Options{OPT.'SleepSchemes'}} = %SleepSchemes;
		%{$::Options{OPT.'WakeSchemes'}} = %WakeSchemes;
		
		$::Options{OPT.'LastActiveSleepScheme'} = $SleepSchemes{default1}->{label}; 
		$::Options{OPT.'LastActiveWakeScheme'} = $WakeSchemes{default1}->{label}; 
		
		$::Options{OPT.'firstrun'} = 1;
	}
	else
	{
		%SleepSchemes = %{$::Options{OPT.'SleepSchemes'}};
		%WakeSchemes = %{$::Options{OPT.'WakeSchemes'}};
		
		if (($::Options{OPT.'ActiveAlarms'}) and ($::Options{OPT.'Advanced_KeepAlarms'}))
		{
			#we must do tempalarm, since opt.activeAlarms is modified during loop if more than one alarm to launch
			my @tempAlarms = @{$::Options{OPT.'ActiveAlarms'}};
			for (@tempAlarms) 
			{
				my %Alarm = %{$_};
			
				#clean old ids and handles from alarms
				delete $Alarm{activealarmid} if ($Alarm{activealarmid}); 
				delete $Alarm{alarmhandle} if ($Alarm{alarmhandle});
				delete $Alarm{waitingforlaunchtime} if ($Alarm{waitingforlaunchtime});

				#only launch 'em if repeat is set for Wake, automatic_launch for Sleepmodes
				#also remove automatically launched sleepalarm, if repeat is not set and it's alarmtime has passed
				next if (($Alarm{type} eq 'Wake') and (!$Alarm{lc($Alarm{type}).'repeatcheck'}));
				next if (($Alarm{type} eq 'Sleep') and (!$Alarm{launchautomaticallycheck}));
				next if (($Alarm{type} eq 'Sleep') and (defined $Alarm{finishingtime}) and ($Alarm{finishingtime} < time) and (!$Alarm{sleeprepeatcheck}) and ($Alarm{launchautomaticallycheck}));

				$Alarm{relaunch} = 1; #tell everybody we're recycling
				
				LaunchSunshine(force => $Alarm{type}, Alarm_ref => \%Alarm, silent => 1);
			}
		}
	}
	
}
sub Stop
{
	if ($::Options{OPT.'ShowButton'} == 1){Layout::RegisterWidget('Sunshine');}

	$notify = undef;
	::UnWatch($handle,'PlayingSong');
	Glib::Source->remove($handle) if $handle; $handle=undef;	
	Glib::Source->remove($notifyhandle) if $notifyhandle; $notifyhandle=undef;	
	Glib::Source->remove(${$_}{alarmhandle}) for (@ActiveAlarms);
		
}

sub SaveSchemes
{
	%{$::Options{OPT.'SleepSchemes'}} = %SleepSchemes;
	%{$::Options{OPT.'WakeSchemes'}} = %WakeSchemes;

	return 1;
}

sub DisableWidgets
{
	# set sleepmodelabel/combo, if multimode is on
	my $realScheme = GetRealScheme('Sleep',$::Options{OPT.'LastActiveSleepScheme'});
	my $sen = ($SleepSchemes{$realScheme}->{multisleepmodeison})? 0 : 1;
	my $lText = ($sen)? ' Sleepmode: ' : ' Sleepmode:  [CUSTOM]';

	$prefWidgets{sleeplabel1}->{widget}->set_text($lText);
	$prefWidgets{sleepmodecombo}->{widget}->set_sensitive($sen);

	#disable 2 or 3 of these widgets depending on sleepmode
	my @smsen = (0,0,0);
	
	if (($SleepSchemes{$realScheme}->{multisleepmodeison})){
		for (@{$SleepSchemes{$realScheme}->{multisleepmodes}}) {
			$smsen[0] = 1 if ($_ eq 'queue');
			$smsen[1] = 1 if ($_ eq 'simpletime');
			$smsen[2] = 1 if ($_ eq 'simplecount');
		}
	}
	else { 
		$smsen[0] = ($prefWidgets{sleepmodecombo}->{widget}->get_active_text eq $SleepModes{queue}->{label});
		$smsen[1] = ($prefWidgets{sleepmodecombo}->{widget}->get_active_text eq $SleepModes{simpletime}->{label});
		$smsen[2] = ($prefWidgets{sleepmodecombo}->{widget}->get_active_text eq $SleepModes{simplecount}->{label});
	}
		
	$prefWidgets{ignorelastinqueue}->{widget}->set_sensitive($smsen[0]); 
	$prefWidgets{simpletime}->{widget}->set_sensitive($smsen[1]); 
	$prefWidgets{simplecount}->{widget}->set_sensitive($smsen[2]);
		
	#disable remove scheme - button if only 1 scheme left
	for my $type ('sleep','wake')
	{
		my $model = $prefWidgets{$type.'schemecombo'}->{widget}->get_model;
		$prefWidgets{$type.'button_remove'}->{widget}->set_sensitive(($model->iter_n_children != 1));
	}
	
	#check that friendwidgets are properly set
	for my $curKey (sort keys %prefWidgets)	{
		next if (ref($prefWidgets{$curKey}) eq 'ARRAY');
		next unless ($prefWidgets{$curKey}->{type} =~ /CheckButton/);
		for (@{$prefWidgets{$curKey}->{friendwidgets}}){
			#disable friendwidget if there's a condition that returns TRUE
			if (($prefWidgets{$_}->{friendcondition}) and (eval($prefWidgets{$_}->{friendcondition}))) {$prefWidgets{$_}->{widget}->set_sensitive(0);}
			else {$prefWidgets{$_}->{widget}->set_sensitive($prefWidgets{$curKey}->{widget}->get_active);}
		}
	}
	
	#set wakelaunchtimes
	$realScheme = GetRealScheme('Wake',$::Options{OPT.'LastActiveWakeScheme'});
	$sen = ($WakeSchemes{$realScheme}->{wakecustomtimes})? 0 : 1;
	$lText = ($sen)? ' Wake up at: ' : ' Wake up at:  [CUSTOM]';

	$prefWidgets{wakelaunchhour}->{widget}->set_sensitive($sen); 
	$prefWidgets{wakelaunchmin}->{widget}->set_sensitive($sen);
	$prefWidgets{wakelabel1}->{widget}->set_text($lText) if ($lText ne $prefWidgets{wakelabel1}->{widget}->get_text);

	return 1;
}

sub NameDialog
{
	my ($WantedAction,$oldScheme) = @_;
	
	my $NameDialog = Gtk2::Dialog->new($WantedAction, undef, 'modal');
	$NameDialog->add_buttons('gtk-cancel' => 'cancel','gtk-ok' => 'ok');
	my $text;
	
	$NameDialog->set_position('center-always');
	
	my $NameEntry;
	if ($WantedAction !~ /Remove/) 
	{ 
		$text = ($WantedAction =~ /Rename/)? $oldScheme : 'New Scheme';
		$NameEntry = Gtk2::Entry->new(); 
		$NameEntry->set_text($text);
		$NameEntry->signal_connect(changed => sub { $text = $NameEntry->get_text;});
		$NameEntry->signal_connect(activate => sub { $NameDialog->response('ok'); });
	}
	else {$NameEntry = Gtk2::Label->new('About to remove scheme \''.$oldScheme.'\'.');}

	$NameDialog->get_content_area()->add($NameEntry) if (defined $NameEntry);
	$NameDialog->set_default_response ('cancel');
	$NameDialog->show_all;

	my $response = $NameDialog->run;

	$NameDialog->destroy();
	return ($response,$text);
}

sub ShowAdvancedSettings
{
	# Todo: 	
	# custom layout button functions

	my $Dialog = Gtk2::Dialog->new('Advanced Settings', undef, 'modal');
	my %LastSetup; my @commandlist;
	
	for (keys %AdvancedDefaults) { $LastSetup{$_} = $::Options{OPT.'Advanced_'.$_}; }
	
	$Dialog->add_buttons('gtk-ok' => 'ok', 'gtk-cancel','cancel');
	$Dialog->set_position('center-always');

	my @aa; for (@ActiveAlarms) { push @aa, $_->{label};}
	my $activealarmskillbox = ::NewPrefCombo(OPT.'A_ActiveAlarmsBox',\@aa);
	@aa = @ActiveAlarms;
	my $activealarmskillbutton; $activealarmskillbutton = ::NewIconButton('gtk-delete','Kill this',sub 
		{
			RemoveAlarm($aa[$activealarmskillbox->get_active]);
			UpdateStatusTexts();
			$activealarmskillbox->remove_text($activealarmskillbox->get_active);
			if (!scalar@ActiveAlarms){ $activealarmskillbox->set_sensitive(0); $activealarmskillbutton->set_sensitive(0);}
			else {$activealarmskillbox->set_active(0);}
			
		}); 
	my $activealarmskilllabel = Gtk2::Label->new('Active Alarms ');
	
	if (!scalar@ActiveAlarms){ $activealarmskillbox->set_sensitive(0); $activealarmskillbutton->set_sensitive(0);}
	
	for (sort keys %SleepWakeCommands) { push @commandlist, $SleepWakeCommands{$_}->{label};}
	my $sleepcommand = ::NewPrefCombo(OPT.'A_SleepCommandBox',\@commandlist,text => 'Sleepcommand', cb => 
		sub {
			for (keys %SleepWakeCommands) { if ($SleepWakeCommands{$_}->{label} eq $::Options{OPT.'A_SleepCommandBox'}) 
				{$::Options{OPT.'Advanced_SleepCommand'} = $SleepWakeCommands{$_}->{command}; last;}}
		});
	my $wakecommand = ::NewPrefCombo(OPT.'A_WakeCommandBox',\@commandlist,text => 'Wakecommand', cb =>
		sub {
			for (keys %SleepWakeCommands) { if ($SleepWakeCommands{$_}->{label} eq $::Options{OPT.'A_WakeCommandBox'}) 
				{$::Options{OPT.'Advanced_WakeCommand'} = $SleepWakeCommands{$_}->{command}; last;}}
		});

	my $volumefadeinperc = ::NewPrefSpinButton(OPT.'Advanced_VolumeFadeInPerc',10,100, text1 => 'Finish volumefade in ', text2=> '% of fadelength');
	my $multiplealarms = ::NewPrefCheckButton(OPT.'Advanced_MultipleAlarms','Allow multiple alarms', tip => 'If unchecked, Sunshine will allow only one sleep- and one wake-alarm at time. Old alarms will be removed when new is started.');
	my $keepalarms = ::NewPrefCheckButton(OPT.'Advanced_KeepAlarms','Keep alarms between sessions', tip => 'If unchecked, Sunshine will disable all active alarms when gmusicbrowser is shut down.');
	my $morenots = ::NewPrefCheckButton(OPT.'Advanced_MoreNotifications','More notifications!', tip => 'Nice pop-up every now and then, now who wouldn\'t like that?');
	my $ar = ::NewPrefCheckButton(OPT.'Advanced_Albumrandom','Launch Albumrandom when waking', tip => 'This obviously doesn\'t work unless Albumrandom-plugin is installed and enabled');
	my $skipalarmifplaying = ::NewPrefCheckButton(OPT.'Advanced_SkipAlarmIfPlaying','Don\'t launch alarmcommand if music is already playing', tip => 'This just in case you happen to wake up before alarm and start music manually');
	my $ignorelastcount = ::NewPrefCheckButton(OPT.'Advanced_IgnoreLastInCount','Count current song in count-mode', tip => 'By default, songcount begins only from first whole song to be played, you can change this here.');
	my $dontfinishlast = ::NewPrefCheckButton(OPT.'Advanced_DontFinishLastInTimed',"Don't finish last song in timed mode", tip => 'Did you know that he fourth wise monkey is called Shizaru?');
	my $manusleepspin = ::NewPrefSpinButton(OPT.'Advanced_ManualTimeSpin',1,720, text2=> ' minutes instead');
	my $manualsleeptime = ::NewPrefCheckButton(OPT.'Advanced_ManualFadeTime',"Don't calculate sleep-modes' fadetime, but use ", 
		tip => 'Calculating might go wrong if you\'re playing random tracks, since they are re-generated when played', widget => $manusleepspin);
	my $label1 = Gtk2::Label->new("Please note that some of these settings might have non-obvious effects!\nCheck the README before changing unless you know what you're doing.");

	#disable albumrandom-option if can't find plugin
	eval('GMB::Plugin::ALBUMRANDOM::IsAlbumrandomOn()');
	my $s = ($@)? 0 : 1;
	$ar->set_sensitive($s); $ar->set_active($s);
	$::Options{OPT.'Advanced_Albumrandom'} = $s;
	
	my $vbox = ::Vpack($label1,[$activealarmskilllabel,'_',$activealarmskillbox,$activealarmskillbutton],[$multiplealarms,$keepalarms],[$morenots,$ar],[$ignorelastcount,$dontfinishlast],
		[$skipalarmifplaying],$volumefadeinperc,$manualsleeptime,[$sleepcommand,$wakecommand]);

	$Dialog->get_content_area()->add($vbox);
	$Dialog->set_default_response ('cancel');	
	$Dialog->show_all;

	my $response = $Dialog->run;

	$Dialog->destroy();

	#cancel => return values as they were
	if ($response eq 'cancel'){for (keys %AdvancedDefaults) { $::Options{OPT.'Advanced_'.$_} = $LastSetup{$_}; }}

	return 1;	
}

sub SelectMultiSleepmode
{
	my $realScheme = GetRealScheme('Sleep',$::Options{OPT.'LastActiveSleepScheme'});
	
	my $Dialog = Gtk2::Dialog->new('Select Sleepmodes', undef, 'modal');
	my @LastSetup = (); 
	my $lastmodeison = $SleepSchemes{$realScheme}->{multisleepmodeison} || 0;
	my $lastmodereq = $SleepSchemes{$realScheme}->{multisleepmoderequireall} || 0;
	
	if ($SleepSchemes{$realScheme}->{multisleepmodeison}) { for (@{$SleepSchemes{$realScheme}->{multisleepmodes}}) { push @LastSetup, $_; }}
	
	$Dialog->add_buttons('gtk-ok' => 'ok', 'gtk-cancel','cancel');
	$Dialog->set_position('center-always');

	my @boxes = ();
	for my $key (sort keys %SleepModes)
	{
		push @boxes, Gtk2::CheckButton->new($SleepModes{$key}->{label});
		$boxes[$#boxes]->set_active(0);
		for my $mode (@{$SleepSchemes{$realScheme}->{multisleepmodes}}) {
			if ($key eq $mode) {$boxes[$#boxes]->set_active(1); last;} 
		}
	}
	
	my $combo = Gtk2::ComboBox->new_text;
	$combo->append_text('Require ANY of selected');
	$combo->append_text('Require ALL of selected');
	$combo->set_active($SleepSchemes{$realScheme}->{multisleepmoderequireall} || 0);
	$combo->signal_connect(changed => sub { $SleepSchemes{$realScheme}->{multisleepmoderequireall} = $combo->get_active;});
	
	my $vbox = ::Vpack(@boxes,$combo);

	$Dialog->get_content_area()->add($vbox);
	$Dialog->set_default_response ('cancel');	
	$Dialog->show_all;

	my $response = $Dialog->run;

	#cancel => return values as they were
	if ($response eq 'cancel'){
		@{$SleepSchemes{$realScheme}->{multisleepmodes}} = (); 	
		push @{$SleepSchemes{$realScheme}->{multisleepmodes}}, $_ for (@LastSetup);
		$SleepSchemes{$realScheme}->{multisleepmodeison} = $lastmodeison;
		$SleepSchemes{$realScheme}->{multisleepmoderequireall} = $lastmodereq;
	}
	else
	{
		@{$SleepSchemes{$realScheme}->{multisleepmodes}} = ();
		
		for my $boxnum (0..((keys %SleepModes)-1))
		{
			# find corresponding key for check-label
			my @boxkeys = grep { $SleepModes{$_}->{label} eq $boxes[$boxnum]->get_label} keys %SleepModes;
			if (scalar@boxkeys == 1) { 
				push @{$SleepSchemes{$realScheme}->{multisleepmodes}}, $boxkeys[0] if ($boxes[$boxnum]->get_active); 
			}
			else {warn "SUNSHINE: Strange number of items in \@boxkeys at SelectMultiSleepmode!";}
		}
		
		# make sure nothing's in table twice			
		my %unique; %unique = map { $_ => 1 } @{$SleepSchemes{$realScheme}->{multisleepmodes}};
		@{$SleepSchemes{$realScheme}->{multisleepmodes}} = keys %unique;
		
		$SleepSchemes{$realScheme}->{multisleepmodeison} = (scalar@{$SleepSchemes{$realScheme}->{multisleepmodes}})? 1 : 0;
	}
	$Dialog->destroy();

	return 1;	
}

sub SetCustomTimes
{
	my $realScheme = GetRealScheme('Wake',$::Options{OPT.'LastActiveWakeScheme'});
	
	my $Dialog = Gtk2::Dialog->new('Edit custom times', undef, 'modal');
	$Dialog->add_buttons('gtk-ok' => 'ok');
	$Dialog->set_position('center-always');
	my @DayChecks;
	my @Hour; my @Min;
	my $Label = Gtk2::Label->new(':');
	my @InitH; my @InitM; my @InitC;

	#init values from wakestring or from prefs
	for (0..6) {
		push @InitH, $prefWidgets{wakelaunchhour}->{widget}->get_value;
		push @InitM, $prefWidgets{wakelaunchmin}->{widget}->get_value;
		push @InitC, 0;
	}
	
	if ($WakeSchemes{$realScheme}->{wakecustomtimes})
	{
		foreach my $timestring (@{$WakeSchemes{$realScheme}->{wakecustomtimestrings}})
		{
			next unless ($timestring =~ /^(\D{3})?\:?(\d{1,2})\:(\d{1,2})$/);
			$InitH[$dayvalues{$1}] = $2;
			$InitM[$dayvalues{$1}] = $3;
			$InitC[$dayvalues{$1}] = 1;
		}	
	}

	for (0..6) 
	{
		push @Hour, Gtk2::SpinButton->new(Gtk2::Adjustment->new(0,0,23,1,10,0),1,0);
		push @Min, Gtk2::SpinButton->new(Gtk2::Adjustment->new(0,0,59,1,10,0),1,0);
		push @DayChecks, Gtk2::CheckButton->new($daynames[$_]); 

		$Hour[$_]->set_wrap(1); $Min[$_]->set_wrap(1);
		$Hour[$_]->set_value($InitH[$_]);
		$Min[$_]->set_value($InitM[$_]);
		$DayChecks[$_]->set_active($InitC[$_]);
		
	}
	
	my @rows;
	for (1..6) { push @rows, ::Hpack('_',$DayChecks[$_],$Hour[$_],$Min[$_]);}
	push @rows, ::Hpack('_',$DayChecks[0],$Hour[0],$Min[0]);#make sunday last
	
	my $vbox = ::Vpack(@rows);

	$Dialog->get_content_area()->add($vbox);
	$Dialog->set_default_response ('cancel');	
	$Dialog->show_all;

	my $response = $Dialog->run;

	$Dialog->destroy();
	
	$WakeSchemes{$realScheme}->{wakecustomtimes} = 0;
	@{$WakeSchemes{$realScheme}->{wakecustomtimestrings}} = ();
	for (0..6) {$WakeSchemes{$realScheme}->{wakecustomtimes} = 1 if ($DayChecks[$_]->get_active);} 
	
	if ($WakeSchemes{$realScheme}->{wakecustomtimes})
	{
		for (0..6)	{
			next unless ($DayChecks[$_]->get_active);
			push @{$WakeSchemes{$realScheme}->{wakecustomtimestrings}}, $daynames[$_].':'.$Hour[$_]->get_value.':'.$Min[$_]->get_value;
		}
	}
	
	return ($response);
}

sub UpdateWidgetsFromScheme
{
	my ($type,$scheme) = @_;

	return unless $type;
	if (not defined $scheme){
		$scheme = GetRealScheme($type,$::Options{OPT.'LastActive'.$type.'Scheme'});
		$scheme = ($type eq 'Sleep')? $SleepSchemes{$scheme} : $WakeSchemes{$scheme};
	}

	for my $curKey (sort keys %prefWidgets)	{
		my $curW = $prefWidgets{$curKey};
		next if ((ref($curW) eq 'ARRAY') or ($curW->{mode} !~ /$type/) or ($curW->{noupdate}));

		if ($curW->{type} eq 'CheckButton') {
			$curW->{widget}->set_active($scheme->{$curKey} || 0);
		}
		elsif ($curW->{type} eq 'SpinButton') {
			if ((defined $scheme->{$curKey}) and ($scheme->{$curKey} =~ /^\'(\d+)\'$/)) {$scheme->{$curKey} = $1;}
			$curW->{widget}->set_value((defined $scheme->{$curKey})? $scheme->{$curKey} : ($curW->{defaultvalue} || 1));
		}
		elsif ($curW->{type} eq 'Entry') {
			$curW->{widget}->set_text($scheme->{$curKey} || '');
		}
		elsif ($curW->{type} eq 'ComboBox') 
		{
			my $model = $curW->{widget}->get_model;
			my $itemcount = ($model->iter_n_children-1);
			my $iter;

			if ($scheme->{$curKey})	{
				for (0..$itemcount)	{
					$iter = $model->iter_nth_child(undef,$_);
					my @values = $model->get($iter);
					if ($scheme->{$curKey} eq $values[0]) { $curW->{widget}->set_active($_); last;}
				}
			}
			else { 
				if ($curW->{widget}->get_active == -1){
					if ((defined $curW->{defaultvalue}) and ($curW->{defaultvalue} <= $itemcount)) {$curW->{widget}->set_active($curW->{defaultvalue});}
					else {$curW->{widget}->set_active(0);}
				}
			}
		}
	}
	
	if ($type =~ /Sleep/)
	{
		#set sleepmodecombo
		my @scItems;
		push @scItems, $SleepModes{$_}->{label} for (keys %SleepModes);
		@scItems = sort @scItems;
		my ($num) = grep {$SleepModes{$scheme->{sleepmode}}->{label} eq $scItems[$_]} (0..$#scItems);
		$prefWidgets{sleepmodecombo}->{widget}->set_active($num) if (defined $num);
	}

	DisableWidgets();

	return 1;
}

sub HandleNewRenameScheme
{
	my ($type,$oldSch,$newtext) = @_;
	
	#  Having $oldSch tells us whether we are renaming or creating new scheme
	if (not defined $oldSch){ $oldSch = CreateNewScheme($type);}
	
	if (not defined $oldSch){ warn "SUNSHINE: Something gone wrong when trying to handle schemes!"; return undef;}
	
	if ($type =~ /Sleep/) {$SleepSchemes{$oldSch}->{label} = $newtext if ($newtext);}
	else {$WakeSchemes{$oldSch}->{label} = $newtext if ($newtext);}

	return $oldSch;	
}

sub CreateNewScheme
{
	my $type = shift;
	my $realScheme;
	
	#find first free 'userNUM'
	for my $num (1..1000) { 
		my ($found) = grep { 'user'.$num eq $_} ($type =~ /Sleep/)? (sort keys %SleepSchemes) : (sort keys %WakeSchemes); 
		if (not defined $found) { $realScheme = 'user'.$num; last;}
	}
	return undef unless $realScheme;

	#set necessary initialvalues
	my %CurScheme = ($type =~ /Sleep/)? %SleepSchemes : %WakeSchemes;
	$CurScheme{$realScheme}->{type} = $type;
	$CurScheme{$realScheme}->{schemekey} = $realScheme;
	$CurScheme{$realScheme}{sleepmode} = 'immediate' if ($type eq 'Sleep');
	$CurScheme{$realScheme} = SetDefaultFilterSort($CurScheme{$realScheme}) if ($type eq 'Wake');

	for my $curKey (keys %prefWidgets)
	{
		my $curW = $prefWidgets{$curKey};
		next if ((ref($curW) eq 'ARRAY') or ($curW->{mode} ne $type) or ($curW->{noupdate}));
			
		if (defined $curW->{defaultvalue}){$CurScheme{$realScheme}{$curKey} = $curW->{defaultvalue};}
		if ($curW->{type} eq 'ComboBox') {$CurScheme{$realScheme}{$curKey} = $curW->{widget}->get_active_text;}
	}
		
	#finally send to real table
	if ($type eq 'Sleep') { $SleepSchemes{$realScheme} = $CurScheme{$realScheme}; }
	else{$WakeSchemes{$realScheme} = $CurScheme{$realScheme};}
	
	return $realScheme;
	
}

sub HandleTopButtonResponse
{
	my ($type,$key,$realScheme,$newtext) = @_;
	
	$EditingScheme = 1;
	
	my %CurScheme = ($type =~ /Sleep/)? %SleepSchemes : %WakeSchemes;
	$realScheme = GetRealScheme($type,$prefWidgets{lc($type).'schemecombo'}->{widget}->get_active_text);

	if ($prefWidgets{$key}->{action} eq 'Remove'){ 
		if ($type =~ /Sleep/) {delete $SleepSchemes{$realScheme};}
		else {delete $WakeSchemes{$realScheme};}
		$realScheme = undef;
	}
	else
	{
		my $oldScheme = ($prefWidgets{$key}->{action} eq 'New')? undef : $realScheme; 
		$realScheme = HandleNewRenameScheme($type,$oldScheme,$newtext);
	}

	#we have to 'reload' curscheme because of changes
	for (keys %CurScheme) { $prefWidgets{lc($type).'schemecombo'}->{widget}->remove_text(0);}
	%CurScheme = ($type =~ /Sleep/)? %SleepSchemes : %WakeSchemes;
	my @Items=();
	push @Items, $CurScheme{$_}->{label} for (keys %CurScheme);
	@Items = sort @Items;

	#re-populate schemecombo
	for (0..$#Items)
	{
		$prefWidgets{lc($type).'schemecombo'}->{widget}->append_text($Items[$_]);
		$prefWidgets{lc($type).'schemecombo'}->{widget}->set_active($_) if ((not defined $realScheme) or ($Items[$_] eq $CurScheme{$realScheme}->{label}));
	}

	$realScheme = GetRealScheme($type,$prefWidgets{lc($type).'schemecombo'}->{widget}->get_active_text);

	#disable remove-button if there is only one scheme left
	my $model = $prefWidgets{lc($type).'schemecombo'}->{widget}->get_model;
	$prefWidgets{$key}->{widget}->set_sensitive(($model->iter_n_children != 1));
						
	UpdateWidgetsFromScheme($type,$CurScheme{$realScheme});
	$::Options{OPT.'LastActive'.$type.'Scheme'} = $prefWidgets{lc($type).'schemecombo'}->{widget}->get_active_text;
	
	$EditingScheme = 0;
	SaveSchemes;
	
	return 1;
}
sub CreateTopButtons
{
	for my $type ('Sleep','Wake')
	{
		my $scheme = $prefWidgets{lc($type).'schemecombo'}->{widget}->get_active_text;
		my $realScheme = GetRealScheme($type,$scheme);
	
		for my $key (sort keys %prefWidgets)
		{
			next if (ref($prefWidgets{$key}) eq 'ARRAY');
			next unless ($prefWidgets{$key}->{mode} eq $type.'TopButton');
		
			$prefWidgets{$key}->{widget} = ::NewIconButton($prefWidgets{$key}->{pic},$prefWidgets{$key}->{text});
			$prefWidgets{$key}->{widget}->signal_connect(clicked => sub 
				{
					my ($resp,$newtext) = NameDialog($prefWidgets{$key}->{action}.' scheme',$prefWidgets{lc($type).'schemecombo'}->{widget}->get_active_text);
					if ($resp eq 'ok'){ if (HandleTopButtonResponse($type,$key,$realScheme,$newtext) != 1) {warn "SUNSHINE: HandleTopButtonResponse was not right."}}
				});
		}
	}
	
	return 1;
}

sub CreateWidgets
{
	for my $type ('Sleep','Wake')
	{
		my %CurScheme = ($type =~ /Sleep/)? %SleepSchemes : %WakeSchemes;
		my $realScheme = GetRealScheme($type,$::Options{OPT.'LastActive'.$type.'Scheme'});

		for my $curKey (sort keys %prefWidgets)	
		{
			my $curW = $prefWidgets{$curKey};
			
			next if (ref($curW) eq 'ARRAY');
			next unless ($curW->{mode} =~ /$type/); #only load needed widgets

			if ($curW->{type} eq 'CheckButton') {
				$curW->{widget} = Gtk2::CheckButton->new($curW->{text});
				$curW->{widget}->signal_connect(clicked => 
				sub { 
					$realScheme = GetRealScheme($curW->{mode},$prefWidgets{lc($curW->{mode}).'schemecombo'}->{widget}->get_active_text);
					$CurScheme{$realScheme}->{$curKey} = $curW->{widget}->get_active;
					for (@{$curW->{friendwidgets}}){
							#if we have a 'friendcondition' which returns TRUE, we don't set friendwidgets' status on change
							$prefWidgets{$_}->{widget}->set_sensitive($CurScheme{$realScheme}->{$curKey}) unless (($prefWidgets{$_}->{friendcondition}) and (eval($prefWidgets{$_}->{friendcondition})));
					}
					SaveSchemes;
				});
			}
			elsif ($curW->{type} eq 'Button') {
				$curW->{widget} = Gtk2::Button->new($curW->{text});
				$curW->{widget}->signal_connect(clicked => eval($prefWidgets{$curKey}->{func}));
			}
			elsif ($curW->{type} eq 'IconButton') {
				$curW->{widget} = ::NewIconButton($curW->{pic},$curW->{text});
				$curW->{widget}->signal_connect(clicked => $curW->{func}); 
				
			}
			elsif ($curW->{type} eq 'SpinButton') {
				my $adj = eval($curW->{adjust});
				$curW->{widget} = Gtk2::SpinButton->new($adj,1,0);

				$curW->{widget}->set_wrap(1) if ($curW->{wrap});
				$curW->{widget}->signal_connect(value_changed => 
				sub { 
					$realScheme = GetRealScheme($curW->{mode},$prefWidgets{lc($curW->{mode}).'schemecombo'}->{widget}->get_active_text); 
					$CurScheme{$realScheme}->{$curKey} = $curW->{widget}->get_value;
					SaveSchemes;
				});
			}
			elsif ($curW->{type} eq 'Label') {
				$curW->{widget} = Gtk2::Label->new($curW->{text});
				$curW->{widget}->set_alignment(0,.5);
			}
			elsif ($curW->{type} eq 'Entry') {
				$curW->{widget} = Gtk2::Entry->new();
				$curW->{widget}->signal_connect(changed => 
				sub { 
					$realScheme = GetRealScheme($curW->{mode},$prefWidgets{lc($curW->{mode}).'schemecombo'}->{widget}->get_active_text); 
					$CurScheme{$realScheme}->{$curKey} = $curW->{widget}->get_text;
					SaveSchemes;
				});
			}
			elsif ($curW->{type} eq 'ComboBox')
			{
				#signals for scheme- and sleepmode-combos are created in CreateSignals
				$curW->{widget} = Gtk2::ComboBox->new_text; 
			 
				my @Items=();
				if ($curKey =~ /(.+)schemecombo$/)
				{
					push @Items, $CurScheme{$_}->{label} for (sort keys %CurScheme);
					@Items = sort @Items;

					for (0..$#Items){
						$curW->{widget}->append_text($Items[$_]);
						$curW->{widget}->set_active($_) if ($Items[$_] eq $CurScheme{$realScheme}->{label});
					}
				}
				elsif ($curKey eq 'sleepmodecombo')
				{ 
					@Items = ();
					push @Items, $SleepModes{$_}->{label} for (keys %SleepModes);
					@Items = sort @Items;
					$curW->{widget}->append_text($_) for (@Items);
					my ($nsID) = grep { $Items[$_] eq $SleepModes{$CurScheme{$realScheme}->{sleepmode}}->{label} } 0..$#Items;
					$curW->{widget}->set_active($nsID || 0);
				}
				else
				{
					if  ($curKey eq 'wakestartfromcombo') { @Items = @StartFromItems;}
					else { warn "ERROR: Sunshine tried to create undefined ComboBox."; next;}

					for (0..$#Items){
						$curW->{widget}->append_text($Items[$_]);
					}
					$curW->{widget}->signal_connect(changed => 
					sub {
						$realScheme = GetRealScheme($curW->{mode},$prefWidgets{lc($curW->{mode}).'schemecombo'}->{widget}->get_active_text);
						$CurScheme{$realScheme}->{$curKey} = $curW->{widget}->get_active_text;
						SaveSchemes;
					});
				}
				
			}
			$prefWidgets{$curKey} = $curW; #set back to real table
		}
	}
	
	return 1;
}

sub CreateSignals
{
	#first sleep-related
	my $realScheme;

	$prefWidgets{sleepschemecombo}->{widget}->signal_connect(changed => 
	sub	{
		return if ($EditingScheme);
		SaveSchemes;
		for (keys %SleepSchemes) {
			if ($SleepSchemes{$_}->{label} eq $prefWidgets{sleepschemecombo}->{widget}->get_active_text) { $realScheme = $_; last;}
		}
		return unless $realScheme;
		UpdateWidgetsFromScheme('Sleep',$SleepSchemes{$realScheme});
		$::Options{OPT.'LastActiveSleepScheme'} = $prefWidgets{sleepschemecombo}->{widget}->get_active_text;
	});

	$prefWidgets{sleepmodecombo}->{widget}->signal_connect(changed => 
	sub	{
			return if ($EditingScheme);
			$realScheme = GetRealScheme('Sleep',$prefWidgets{sleepschemecombo}->{widget}->get_active_text);
			DisableWidgets();
			for (keys %SleepModes)	{
				$SleepSchemes{$realScheme}->{sleepmode} = $_ if ($SleepModes{$_}->{label} eq $prefWidgets{sleepmodecombo}->{widget}->get_active_text); 	
			}
	});

	#then wake
	$realScheme = GetRealScheme('Wake',$prefWidgets{wakeschemecombo}->{widget}->get_active_text);

	$prefWidgets{wakeschemecombo}->{widget}->signal_connect(changed => 
	sub	{
		return if ($EditingScheme);
		SaveSchemes;
		for (keys %WakeSchemes) {
			if ($WakeSchemes{$_}->{label} eq $prefWidgets{wakeschemecombo}->{widget}->get_active_text) { $realScheme = $_; last;}
		}
		return unless $realScheme;
		UpdateWidgetsFromScheme('Wake',$WakeSchemes{$realScheme});
		$::Options{OPT.'LastActiveWakeScheme'} = $prefWidgets{wakeschemecombo}->{widget}->get_active_text;
	});

			
	return 1;	
}

sub GetRealScheme
{
	my ($type,$scheme) = @_;

	my %CurScheme = ($type =~ /Sleep/)? %SleepSchemes : %WakeSchemes;
	my @keys = grep { $CurScheme{$_}->{label} eq $scheme} keys %CurScheme;
	
	return ((scalar@keys)? $keys[0] : undef);
}

sub prefbox
{	
	my @frame=(Gtk2::Frame->new(" Going to sleep "),Gtk2::Frame->new(" Waking up "),Gtk2::Frame->new(" General options "),Gtk2::Frame->new(" Status "));
	my @vbox;

	CreateWidgets();
	CreateTopButtons();
	CreateSignals();
	UpdateWidgetsFromScheme($_) for ('Sleep','Wake');
	DisableWidgets();
	$createdPrefs = 1; #put here, so we can update status'
	UpdateStatusTexts();

	my $sAddAlarm=::NewIconButton('gtk-apply','Activate this scheme', sub { LaunchSunshine(force => 'Sleep');});
	my $wAddAlarm=::NewIconButton('gtk-apply','Activate this scheme', sub { LaunchSunshine(force => 'Wake');});
	my $sCheck1; $sCheck1 = ::NewPrefCheckButton(OPT."SleepEnabled",'Enable Sleepmode',horizontal=>1, cb => sub { $sAddAlarm->set_sensitive($sCheck1->get_active);});
	my $wCheck1; $wCheck1 = ::NewPrefCheckButton(OPT."WakeEnabled",'Enable Wakemode',horizontal=>1, cb => sub { $wAddAlarm->set_sensitive($wCheck1->get_active);});
	$sAddAlarm->set_sensitive($sCheck1->get_active); $wAddAlarm->set_sensitive($wCheck1->get_active);

	my $LaunchButton = ::NewIconButton('gtk-apply','Launch Sunshine!', sub {LaunchSunshine();});
	my $StopButton = ::NewIconButton('gtk-stop','Stop Everything', \&StopSunshine);
	my $mCheck1=::NewPrefCheckButton(OPT."ShowNotifications",'Show notifications', horizontal=>1);
	my $mCheck2=::NewPrefCheckButton(OPT."ShowButton",'Show layout-button', horizontal=>1);
	my $CustomTimes = ::NewIconButton('gtk-properties','Custom', sub { SetCustomTimes(); UpdateWidgetsFromScheme('Wake');});
	my $MultiSleepmode = ::NewIconButton('gtk-properties','', sub { SelectMultiSleepmode(); UpdateWidgetsFromScheme('Sleep');});
	my $mAdvanced = ::NewIconButton('gtk-preferences','Advanced Settings', sub {ShowAdvancedSettings(); SaveSchemes();});
	my $mStatusRefresh=::NewIconButton('gtk-refresh','', sub { UpdateStatusTexts();}, undef, 'Refresh status-texts');
	
	@vbox = (
	::Vpack( [$sCheck1,'-',$sAddAlarm],
			['_',$prefWidgets{sleepschemecombo}->{widget},$prefWidgets{sleepbutton_new}->{widget},$prefWidgets{sleepbutton_rename}->{widget},$prefWidgets{sleepbutton_remove}->{widget}],
			['_',$prefWidgets{sleeplabel1}->{widget},$prefWidgets{sleepmodecombo}->{widget},$MultiSleepmode],
			['_',$prefWidgets{launchautomaticallycheck}->{widget},$prefWidgets{launchautomaticallyhour}->{widget},$prefWidgets{launchautomaticallymin}->{widget}],
			['20',$prefWidgets{sleeprepeatcheck}->{widget}],
			['_',$prefWidgets{svolumefadecheck}->{widget},$prefWidgets{svolumefadefrom}->{widget},
			$prefWidgets{scommonlabel1}->{widget},$prefWidgets{svolumefadeto}->{widget}],
			[$prefWidgets{scommandcheck}->{widget},'_',$prefWidgets{scommandentry}->{widget}],
			[$prefWidgets{shutdowngmb}->{widget}],
			['20',$prefWidgets{shutdowncomputer}->{widget}],
			[$prefWidgets{ignorelastinqueue}->{widget}],
			[$prefWidgets{sleeplabel2}->{widget},$prefWidgets{simpletime}->{widget}],
			[$prefWidgets{sleeplabel3}->{widget},$prefWidgets{simplecount}->{widget}]),
	::Vpack( [$wCheck1,'-',$wAddAlarm],
			['_',$prefWidgets{wakeschemecombo}->{widget},$prefWidgets{wakebutton_new}->{widget},$prefWidgets{wakebutton_rename}->{widget},$prefWidgets{wakebutton_remove}->{widget}],
			[$prefWidgets{wakerepeatcheck}->{widget}],
			['_',$prefWidgets{wakelabel1}->{widget},$prefWidgets{wakelaunchhour}->{widget},$prefWidgets{wakelaunchmin}->{widget},$CustomTimes],
			[$prefWidgets{wvolumefadecheck}->{widget},$prefWidgets{wvolumefadefrom}->{widget},$prefWidgets{wcommonlabel1}->{widget},
			$prefWidgets{wvolumefadeto}->{widget},$prefWidgets{wakelabel2}->{widget},$prefWidgets{wakefadeinmin}->{widget},$prefWidgets{wakelabel3}->{widget}],
			[$prefWidgets{wcommandcheck}->{widget},'_',$prefWidgets{wcommandentry}->{widget}],
			['_',$prefWidgets{wakefiltercheck}->{widget},$prefWidgets{wakefilterbutton}->{widget}],
			['_',$prefWidgets{wakeplaymodecheck}->{widget},$prefWidgets{wakeplaymodebutton}->{widget}],
			[$prefWidgets{wakestartfromcheck}->{widget},'_',$prefWidgets{wakestartfromcombo}->{widget}]),
	::Vpack( [$mCheck1,$mCheck2,'-',$LaunchButton,'-',$StopButton,'-',$mAdvanced]),
	::Vpack( $prefWidgets{sleepstatuslabel}->{widget},[$prefWidgets{wakestatuslabel}->{widget},'-',$mStatusRefresh] ));

	$frame[$_]->add($vbox[$_]) for (0..$#frame);

	return ::Vpack($frame[2],'_',['_',$frame[0],'_',$frame[1]],$frame[3]);
}

sub Notify
{
	my $notify_text = shift;

	return 0 unless ($::Options{OPT.'ShowNotifications'}); 
	
	my $notify_header = 'Sunshine';
	my $notifyshowtime = 5;
	
	push @notifybuffer, $notify_text if (defined $notify_text);
	
	#if previous notify is on, we wait
	if (($lastlaunch+$notifyshowtime) > time){ 
		$notifyhandle = Glib::Timeout->add($notifyshowtime*1000,\&Notify) unless($notifyhandle); 
	}
	else
	{
		return 0 unless (scalar@notifybuffer);
		$notify_text = shift @notifybuffer;
		LaunchNotify($notify_header,$notify_text,$notifyshowtime);

		Glib::Source->remove($notifyhandle) if $notifyhandle; $notifyhandle = undef;
		#launch again, if there's still something
		if (scalar@notifybuffer){
			$notifyhandle = Glib::Timeout->add($notifyshowtime*1000,\&Notify) unless($notifyhandle);
		}
	}
	
	return 0;#must return false to remove timeout
}

sub LaunchNotify
{	
	my ($notify_header,$notify_text,$notifyshowtime) = @_;

	if (not defined $notify)
	{
		eval
		{
			$notify=Gtk2::Notify->new('empty','empty');
			my ($name, $vendor, $version, $spec_version)= Gtk2::Notify->get_server_info;
			$Daemon_name= "$name $version ($vendor)";
			my @caps = Gtk2::Notify->get_server_caps;
			$can_body=	grep $_ eq 'body',	@caps;
			$can_actions=	grep $_ eq 'actions',	@caps;
		};
		if ($@){warn "Sunshine ERROR: Couldn't initialize notifications!"; return 0;};
	}

	$notify->update($notify_header,$notify_text);
	$notify->set_timeout(1000*$notifyshowtime);
	eval{$notify->show;};
	if ($@){warn "Sunshine ERROR: \$notify didn't evaluate properly!";}
	else { $lastlaunch = time;}
	
	return 1;
}

sub RunCommand
{
	my $command = shift;
	
	my @cmd = ::split_with_quotes($command);
	return unless @cmd;
	::forksystem(@cmd);
	
	return 1;
}
sub CheckIfSleepFinished
{
	my %Alarm = %{$_[0]};
	my $finished;

	if ($Alarm{multisleepmodeison})
	{
		my @finishcodes; my @wrongs;
		push @finishcodes, eval($SleepModes{$_}{IsCompleted}) for (@{$Alarm{multisleepmodes}});	

		#all finishcodes that are 0 go to @wrongs
		@wrongs = grep { $_  == 0} @finishcodes;

		# we are finished if requireall == 1 and nothing @wrongs, OR if requireall == 0 and not all items from @finishcodes are in @wrongs
		$finished = ((($Alarm{multisleepmoderequireall}) and (scalar@wrongs)) 
					or 
					((!$Alarm{multisleepmoderequireall}) and (scalar@wrongs == scalar@finishcodes)))? 0 : 1;
	}
	else
	{
		$finished = eval($SleepModes{$Alarm{sleepmode}}{IsCompleted});
		if ($@) {$finished = 0;}
	}
	
	return $finished;
}
sub SleepInterval
{
	my %Alarm = %{$_[0]};
	
	$Alarm{passedtime} += ($Alarm{interval}/1000);#interval is in ms, we want secs

	if ($Alarm{svolumefadecheck})	{
		if (::GetVol() < $Alarm{svolumefadeto}) {::UpdateVol(::GetVol()+1);}
		elsif (::GetVol() > $Alarm{svolumefadeto}) {::UpdateVol(::GetVol()-1);}
		elsif (!$Alarm{newintervalset})
		{
			#we have finished volumefading, so we set interval to finishingtime+1 
			my $newinterval = ($Alarm{finishingtime}-time)+1;
			Glib::Source->remove($Alarm{alarmhandle});
			$Alarm{alarmhandle}=Glib::Timeout->add($newinterval,sub {SleepInterval(\%Alarm);});
			$Alarm{newintervalset} = 1;
		}
	}

	#%Alarm is only a temporary representation, so must send changes back
	%{$_[0]} = %Alarm;
	
	my $finished = CheckIfSleepFinished(\%Alarm);	
	
	if (($finished) and (!$::Options{OPT.'Advanced_DontFinishLastInTimed'})){$Alarm{isfinished} = 1;}
	elsif ($finished) {GoSleep(\%Alarm);}

	return (!$finished);#returning false ends timeout
}
sub SongChanged
{
	return if ($oldID == $::SongID);
	$oldID = $::SongID;
	
	return unless (scalar@ActiveAlarms);
	my @SleepNow;
	
	foreach (@ActiveAlarms)
	{
		my %Alarm = %{$_};
		if ($Alarm{type} eq 'Sleep')
		{
			$Alarm{passedtracks}++;
			my $finished = CheckIfSleepFinished(\%Alarm);

			if (($finished) and (not defined $Alarm{isfinished}))	
			{				
				my @handledalarms;
				my $atleastone = 0;
				if (!$Alarm{multisleepmodeison}){ push @handledalarms, $Alarm{sleepmode};}
				else { @handledalarms = @{$Alarm{multisleepmodes}};}
				
				for my $smode (@handledalarms)
				{
					if ((($smode eq 'queue') and ($Alarm{ignorelastinqueue})) or 
					($smode eq 'albumchange') or 
					(($smode eq 'simplecount') and ($::Options{OPT.'Advanced_IgnoreLastInCount'})))	
					{ 
						$atleastone = 1;
					}
					else {$Alarm{isfinished} = 1;}
				}

			    if ((!$Alarm{multisleepmodeison}) and ($atleastone))   {
					push @SleepNow, \%Alarm;
			    }
			    elsif (($Alarm{multisleepmodeison}) and (
			    (!$Alarm{multisleepmoderequireall}) and ($atleastone)) or
			    (($Alarm{multisleepmoderequireall}) and (not defined $Alarm{isfinished}))) {
					push @SleepNow, \%Alarm;
			    }
			}
			elsif ($finished) { push @SleepNow, \%Alarm; }
			
			%{$_} = %Alarm;
		} 
	}
	
	#do this here, since GoSleep removes items from @activeAlarms, might cause problems in loop^ with multiple alarms
	if (scalar@SleepNow) {GoSleep($_) for (@SleepNow);}

	return 1;
}

sub GoSleep
{
	my %Alarm = %{$_[0]};

	Notify("Finished sleepmode: ".$Alarm{label}."\nGoing to sleep NOW!");

	RemoveAlarm(\%Alarm);
	
	if (($Alarm{sleeprepeatcheck}) and ($Alarm{launchautomaticallycheck}))
	{
		$Alarm{activealarmid} = $Alarm{alarmhandle} = undef;
		$Alarm{initialalbum} = join " ",Songs::Get($::SongID,qw/album_artist album/);
		$Alarm{passedtracks} = $Alarm{passedtime} = 0;

		#no point in repeating, if it would launch immediately again (e.g. empty queue, immediate sleep)
		my $length = CalcSleepLength(\%Alarm);
		if ($length) {LaunchSunshine(force => 'Sleep', Alarm_ref => \%Alarm);}
	}

	UpdateStatusTexts();	
	
	eval($::Options{OPT.'Advanced_SleepCommand'});
	
	if ($Alarm{scommandcheck}) { RunCommand($Alarm{scommandentry});}
	if ($Alarm{shutdowngmb}) 
	{ 
		if ($Alarm{shutdowncomputer}) { ::TurnOff;}
		else {::Quit;} 
	}
	
	return 1;
}
sub AddAlarm
{
	my %Alarm = %{$_[0]};
	my $silent = $_[1];
	
	$Alarm{activealarmid} = scalar@ActiveAlarms;
	push @ActiveAlarms,\%Alarm;
	@{$::Options{OPT.'ActiveAlarms'}} = @ActiveAlarms;
	
	%{$_[0]} = %Alarm;
	#updating statustexts when adding alarms automatically on plugin's launch causes error, since widgets are not yet created
	UpdateStatusTexts() unless (($silent) or (!$createdPrefs));

	return 1;	
}
sub RemoveAlarm
{
	my %Alarm = %{$_[0]};

	Glib::Source->remove($Alarm{alarmhandle}) if (defined $Alarm{alarmhandle});
	if ((defined $Alarm{activealarmid}) and ($Alarm{activealarmid} < $#ActiveAlarms)) {
		for (($Alarm{activealarmid}+1)..$#ActiveAlarms) { ${$ActiveAlarms[$_]}{activealarmid}--;}
	} 
	splice (@ActiveAlarms, $Alarm{activealarmid},1) if (defined $Alarm{activealarmid});

	@{$::Options{OPT.'ActiveAlarms'}} = @ActiveAlarms; 
	%{$_[0]} = %Alarm;

	return 1;	
}

sub GetShortestTimeTo
{
	my @Times = @_;
	my $Now=time;
	my ($cSec,$cMin,$cHour,$cMday,$cMon,$cYear,$cWeekday,$cYday,$cIsdst)= localtime($Now);
	
	# times can be formatted either XXX:??:?? or just ??:??, 
	# where XXX = weekday abbr, and ??:?? hour and minutes, divided by ':'
	# hour & minute might be 1 or 2 digits long
	my $Next=0;
	
	for my $timestring (@Times)
	{
		next unless ($timestring =~ /^(\D{3})?\:?(\d{1,2})\:(\d{1,2})$/);

		my $Hour = $2; my $Min = $3;
		my $Weekday;
		
		if (defined $1) {$Weekday = $dayvalues{$1}} 
		else {$Weekday = ((($Hour*3600)+($Min*60)+(0)) < (($cHour*3600)+($cMin*60)+$cSec))? ($cWeekday+1)%7 : $cWeekday;}
		my $Monthday = ($Weekday == $cWeekday)? $cMday : ($cMday+1);

		my $NextTime = ::mktime(0,$Min,$Hour,$Monthday,$cMon,$cYear);

		if ($Next) { $Next = $NextTime if ($Next > $NextTime);}
		else { $Next = $NextTime;}
	}

	return ($Next-$Now);
}

sub WakeUp
{
	my %Alarm = %{$_[0]};

	#don't launch alarm if a_SAIP is set and music is already playing ($togplay==1)
	if (!(($::Options{OPT.'Advanced_SkipAlarmIfPlaying'}) and ($::TogPlay)))
	{
		if ($Alarm{wvolumefadecheck})
		{
			::UpdateVol($Alarm{wvolumefadefrom});#set starting volume immediately
			
			if ($Alarm{wvolumefadefrom} != $Alarm{wvolumefadeto})
			{
				my $t = int((1000*60*$Alarm{wakefadeinmin})/abs(($Alarm{wvolumefadeto}-$Alarm{wvolumefadefrom})));

				$volumehandle=Glib::Timeout->add($t, 
				sub {
					if (::GetVol() < $Alarm{wvolumefadeto}) {::UpdateVol(::GetVol()+1);}
					elsif (::GetVol() > $Alarm{wvolumefadeto}) {::UpdateVol(::GetVol()-1);}
					else {return 0;}#returning false destroys timeout
					return 1;
				},1);
			}
		}
	
		if ($Alarm{wakefiltercheck}) { ::Select( $Alarm{wselectedfiltertype} => $Alarm{wselectedfilter});}
		if ($Alarm{wakeplaymodecheck}) 
		{ 
			::Select( 'sort' => $Alarm{wselectedsort}); 
			::SetRepeat($Alarm{wselectedsortrepeat}) if ($Alarm{wselectedsortrepeat});
		}
		if ($Alarm{wcommandcheck}) { RunCommand($Alarm{wcommandentry}); }
		if ($Alarm{wakestartfromcheck}){ 
			my $p = ($Alarm{wakestartfromcombo} =~ /First/)? 0 : int(rand(scalar@$::ListPlay));
			::Select(position => $p);
		}

		Notify("Activated alarm '".$Alarm{label}."'\nTime to wake up!");

		if ($::Options{OPT.'Advanced_Albumrandom'}) 
		{ 
			#if we can't launch albumrandom, just go with regular wake
			eval('GMB::Plugin::ALBUMRANDOM::GenerateRandomAlbum()');
   			if ($@){Notify('SUNSHINE: Error! Can\'t launch Albumrandom! Are you sure it\'s enabled?');eval($::Options{OPT.'Advanced_WakeCommand'}); }
   			else {::NextSong(); ::Play();}
		}
		else {eval($::Options{OPT.'Advanced_WakeCommand'});}
	}
	else 
	{ 
		Notify("Alarm '".$Alarm{label}."' skipped because music is already playing!") if ($::Options{OPT.'Advanced_MoreNotifications'});
	}

	RemoveAlarm(\%Alarm);
	UpdateStatusTexts();

	#wait a bit before repeating alarm
	if ($Alarm{wakerepeatcheck}) 
	{ 
		my $repeathandle = Glib::Timeout->add(5000,sub{
			LaunchSunshine(force => 'Wake',Alarm_ref => \%Alarm);
			return 0;	
		});
	}

	return 1; 
}

sub SetDefaultFilterSort
{
	my %scheme = %{$_[0]};
	return unless (%scheme);
	
	$scheme{wselectedfilter} = $::SelectedFilter->{string} if $::SelectedFilter;
	$scheme{wselectedfilter} = ((sort keys %{$::Options{SavedFilters}})[0]) unless ($scheme{wselectedfilter});
	$scheme{wselectedsort} = $::Options{Sort};
	$scheme{wselectedsort} = ((sort keys %{$::Options{SavedSorts}})[0]) unless ($scheme{wselectedsort});
	
	return \%scheme;
}

sub CheckRemovableAlarms
{
	my (%opts) = @_;
	my ($alarmhandle,$type,$silent, $alarmschemekey) = @opts{qw/alarmhandle type silent schemekey/} if (%opts);	
	return unless $type;
	
	for (@ActiveAlarms) 
	{ 
		next unless (${$_}{type} eq $type);
		my $off = 0;

		if ($type eq 'Wake') {
			#remove if multiple alarms not allowed, OR if there's already an alarm by the same type
			$off = 1 if ((!$::Options{OPT.'Advanced_MultipleAlarms'}) or (${$_}{schemekey} eq $alarmschemekey));
		}
		elsif ($type eq 'Sleep'){
			#remove if multiple alarms not allowed, UNLESS there's alarmhandle and it's same as with the new alarm 
			$off = 1 if ((!$::Options{OPT.'Advanced_MultipleAlarms'}) and (!((defined $alarmhandle) and ($alarmhandle == ${$_}{alarmhandle}))));
		}

		if ($off){
			RemoveAlarm($_);
			Notify("Removed previous alarm '".${$_}{label}."'") if (($::Options{OPT.'Advanced_MoreNotifications'}) and (!$silent));
		}
	}

	return 1;
}

sub CalcSleepLength
{
	my %Alarm = %{$_[0]};
	my $modelength=undef;
	
	if ($Alarm{multisleepmodeison})
	{
		# if multisleepreqall == 1 we want longest, otherwise shortest
		for (@{$Alarm{multisleepmodes}})
		{
			my $l = eval($SleepModes{$_}{CalcLength});
			if (($::SongID) and (($_ eq 'queue') or ($_ eq 'albumchange') or ($_ eq 'simplecount'))){
				$l += Songs::Get($::SongID,'length');
				$l -= $::PlayTime if ($::PlayTime);
			}

			if ($@) {warn 'SUNSHINE: Error in CalcSleepLength [1: '.$_.']';}
			elsif (not defined $modelength) {$modelength=$l;}

			$modelength = $l if (($Alarm{multisleepmoderequireall}) and ($modelength < $l));
			$modelength = $l if ((!$Alarm{multisleepmoderequireall}) and ($modelength > $l));
		}
	}
	else 
	{
		$modelength = eval($SleepModes{$Alarm{sleepmode}}{CalcLength});
		if ($@) {warn 'SUNSHINE: Error in CalcSleepLength [2: '.$Alarm{sleepmode}.']';}

		$modelength += (Songs::Get($::SongID,'length') - $::PlayTime) if (($::SongID) and (($_ eq 'queue') or ($_ eq 'albumchange') or ($_ eq 'simplecount')));
	}

	return $modelength;
}
sub LaunchSunshine
{
	my (%opts) = @_;
	my ($Alarm_ref,$force,$silent) = @opts{qw/Alarm_ref force silent/} if (%opts);	
	$force ||= '';

	return unless (($::Options{OPT.'SleepEnabled'}) or ($::Options{OPT.'WakeEnabled'}) or (defined $force));

	if (($force eq 'Sleep') or (($::Options{OPT.'SleepEnabled'}) and ($force ne 'Wake')))
	{
		my $realScheme = GetRealScheme('Sleep',$::Options{OPT.'LastActiveSleepScheme'});
		my %Alarm = %{$Alarm_ref || $SleepSchemes{$realScheme}};

		CheckRemovableAlarms(type => 'Sleep',alarmhandle => $Alarm{alarmhandle},silent => $silent);

		#if we want automatic launch, create an timer to wait for the right moment
		if (($Alarm{launchautomaticallycheck}) and (not defined $Alarm{waitingforlaunchtime})) 
		{
			$Alarm{waitingforlaunchtime} = 1; 
			$Alarm{modelength} = GetShortestTimeTo($Alarm{launchautomaticallyhour}.':'.$Alarm{launchautomaticallymin});
			$Alarm{finishingtime} = time+$Alarm{modelength};
			$Alarm{alarmhandle}=Glib::Timeout->add(1000*$Alarm{modelength},
				sub { $Alarm{waitingforlaunchtime} = 2; LaunchSunshine(force => 'Sleep',type => \%Alarm); return 0;});
			AddAlarm(\%Alarm,$silent);
			Notify("Activated sleepmode: ".$Alarm{label}."\nStarting automatically at ".sprintf("%.2d\:%.2d",$Alarm{launchautomaticallyhour},$Alarm{launchautomaticallymin})) unless ($silent);
		}
		elsif ((not defined $Alarm{waitingforlaunchtime}) or ($Alarm{waitingforlaunchtime} == 2))
		{
			#if we are launching automatically, remove old handle and activealarmid
			if ((defined $Alarm{waitingforlaunchtime}) and ($Alarm{waitingforlaunchtime} == 2)) { RemoveAlarm(\%Alarm); }

			#set initialvalues
			$Alarm{initialalbum} = join " ",Songs::Get($::SongID,qw/album_artist album/);
			$Alarm{passedtracks} = $Alarm{passedtime} = 0;

			# try to calc length for sleepmode
			# this may go wrong if user wants specific number of random songs
			# doesn't matter to finishing, since 'number of random songs' finishes from SongChanged

			$Alarm{modelength} = CalcSleepLength(\%Alarm);

			if (!$Alarm{modelength}) { GoSleep(\%Alarm); return 1;}

			$Alarm{finishingtime} = time+$Alarm{modelength};
			
			if ($Alarm{svolumefadecheck})
			{
				## (-1) in 'from' means we use whatever the volume currently is
				my $fromvol = ($Alarm{svolumefadefrom} == -1)? ::GetVol() : $Alarm{svolumefadefrom};
				if ($::Options{OPT.'Advanced_ManualFadeTime'}) { $Alarm{interval} = $::Options{OPT.'Advanced_ManualTimeSpin'};}
				else {$Alarm{interval} = int(0.5+(1000*$Alarm{modelength}/(abs($Alarm{svolumefadeto}-$fromvol)+1)));}
				
				$Alarm{interval} = int(($Alarm{interval}*$::Options{OPT.'Advanced_VolumeFadeInPerc'})/100);#volumefadeinperc <=> [10,100]
				$Alarm{interval} = 1000 if ($Alarm{interval} < 1000);
				
				# update volume unless we are using (-1) OR if we're relaunching between sessions and have already reached goal (and it's currently set)
				if ($Alarm{svolumefadefrom} > 0) { 
					::UpdateVol($Alarm{svolumefadefrom}) unless (($Alarm{relaunch}) and (::GetVol() == $Alarm{volumefadeto}));
				}
			}
			else{ $Alarm{interval} = 1000*($Alarm{modelength}+1);}

			$Alarm{alarmhandle}=Glib::Timeout->add($Alarm{interval},sub {SleepInterval(\%Alarm);});
			AddAlarm(\%Alarm,$silent);
	 		Notify("Launched '".$Alarm{label}."'.\nGoing to sleep at ".localtime($Alarm{finishingtime})) unless ($silent);
		}
		else {warn "SUNSHINE: Something's wrong in the neighborhood";}
	}
	
	if (($force eq 'Wake') or (($::Options{OPT.'WakeEnabled'}) and ($force ne 'Sleep')))
	{
		my $realScheme = GetRealScheme('Wake',$::Options{OPT.'LastActiveWakeScheme'});
		my %Alarm = %{$Alarm_ref || $WakeSchemes{$realScheme}};

		CheckRemovableAlarms(type => 'Wake', schemekey => $Alarm{schemekey});

		$Alarm{modelength} = ($Alarm{wakecustomtimes})? GetShortestTimeTo(@{$Alarm{wakecustomtimestrings}}) :  GetShortestTimeTo($Alarm{wakelaunchhour}.':'.$Alarm{wakelaunchmin});
		return unless ($Alarm{modelength} > 0);
		$Alarm{finishingtime} = time+$Alarm{modelength};

		$Alarm{alarmhandle}=Glib::Timeout->add($Alarm{modelength}*1000,sub {WakeUp(\%Alarm);});
 		AddAlarm(\%Alarm,$silent);
 		Notify("Launched '".$Alarm{label}."'.\nWaking at ".localtime($Alarm{finishingtime})) unless ($silent);
	}
	
	return 1;
}
sub UpdateStatusTexts
{
	return unless ($createdPrefs);
	my @ts = ("  Sleepmode:\t","  Wakemode:\t");

	for (0..$#ActiveAlarms)
	{
		my %Al = %{$ActiveAlarms[$_]};
		my $left = $Al{finishingtime}-time;
		my $tsindex = ($Al{type} eq 'Sleep')? 0 : 1;

		if ($ts[$tsindex] =~ /^(.+)\t$/) { $ts[$tsindex] .= $Al{label};}
		else {$ts[$tsindex] .= ', '.$Al{label};}
		
		my $timeleft = ' (unable to calculate time)';

		if ($left > 60)	{
			$timeleft = ($left > 86400)? ' (about '.int($left/86400).'d '.int(($left%86400)/3600).'h '.int(($left%3600)/60).'min left)' 
				: ' (about '.int(($left%86400)/3600).'h '.int(($left%3600)/60).' min left)';
		}
		elsif ($left > 0) { $timeleft = ' (under one minute left)';}
		
		$ts[$tsindex] .= $timeleft;
	}
	
	for (0..1) { if ($ts[$_] =~ /^(.+)\t$/) {$ts[$_] .= 'Not active'; }}

	$prefWidgets{sleepstatuslabel}->{widget}->set_text($ts[0]);
	$prefWidgets{wakestatuslabel}->{widget}->set_text($ts[1]);

	return 1;	
}
sub StopSunshine
{
	Glib::Source->remove(${$_}{alarmhandle}) for (@ActiveAlarms);
	@{$::Options{OPT.'ActiveAlarms'}} = @ActiveAlarms = ();	
	Glib::Source->remove($volumehandle) if (defined $volumehandle);
	UpdateStatusTexts();
	Notify('All sleep- and wakemodes deactivated.');
	
	return 1;		
}


sub SortMenu
{	my $nopopup= 0;
	my $menu = Gtk2::Menu->new;
	my $realScheme = GetRealScheme('Wake',$::Options{OPT.'LastActiveWakeScheme'});

	my $check=$WakeSchemes{$realScheme}->{wselectedsort};
	my $found;
	my $callback=sub { $WakeSchemes{$realScheme}->{wselectedsort} = $_[1]; SaveSchemes(); };
	my $append=sub
	 {	my ($menu,$name,$sort,$true,$cb)=@_;
		$cb||=$callback;
		$true=($sort eq $check) unless defined $true;
		my $item = Gtk2::CheckMenuItem->new_with_label($name);
		$item->set_draw_as_radio(1);
		$item->set_active($found=1) if $true;
		$item->signal_connect (activate => $cb, $sort );
		$menu->append($item);
	 };

	my $submenu= Gtk2::Menu->new;
	my $sitem = Gtk2::MenuItem->new(_"Weighted Random");
	for my $name (sort keys %{$::Options{SavedWRandoms}})
	{	$append->($submenu,$name, $::Options{SavedWRandoms}{$name} );
	}
	$sitem->set_submenu($submenu);
	$menu->prepend($sitem);
	$append->($menu,_"Shuffle",'shuffle');

	{ my $item=Gtk2::CheckMenuItem->new(_"Repeat");
	  $item->set_active($WakeSchemes{$realScheme}->{wselectedsortrepeat} || 0);
	  $item->set_sensitive(0) if ($check =~ m/^random:/);
	  $item->signal_connect(activate => sub { $WakeSchemes{$realScheme}->{wselectedsortrepeat} = $_[0]->get_active; SaveSchemes();} );
	  $menu->append($item);
	}

	$menu->append(Gtk2::SeparatorMenuItem->new); #separator between random and non-random modes

	$append->($menu,_"List order", '' ) if defined $::ListMode;
	for my $name (sort keys %{$::Options{SavedSorts}})
	{	$append->($menu,$name, $::Options{SavedSorts}{$name} );
	}
	$menu->show_all;
	return $menu if $nopopup;
	my $event=Gtk2->get_current_event;
	my ($button,$pos)= $event->isa('Gtk2::Gdk::Event::Button') ? ($event->button,\&::menupos) : (0,undef);
	$menu->popup(undef,undef,$pos,undef,$button,$event->time);
}

sub FilterMenu
{	my $nopopup= 0;
	my $menu = Gtk2::Menu->new;
	my $realScheme = GetRealScheme('Wake',$::Options{OPT.'LastActiveWakeScheme'});
	my ($check,$found);

	$check=$WakeSchemes{$realScheme}->{wselectedfilter};
	my $item_callback=sub { $WakeSchemes{$realScheme}->{wselectedfilter} = $_[1]; $WakeSchemes{$realScheme}->{wselectedfiltertype} = 'filter'; SaveSchemes();};

	my $item0= Gtk2::CheckMenuItem->new(_"All songs");
	$item0->set_active($found=1) if !$check && !defined $::ListMode;
	$item0->set_draw_as_radio(1);
	$item0->signal_connect ( activate =>  $item_callback ,'' );
	$menu->append($item0);

	for my $list (sort keys %{$::Options{SavedFilters}})
	{	my $filt=$::Options{SavedFilters}{$list}->{string};
		my $item = Gtk2::CheckMenuItem->new_with_label($list);
		$item->set_draw_as_radio(1);
		$item->set_active($found=1) if defined $check && $filt eq $check;
		$item->signal_connect ( activate =>  $item_callback ,$filt );
		$menu->append($item);
	}
	my $item=Gtk2::CheckMenuItem->new(_"Custom...");
	$item->set_active(1) if defined $check && !$found;
	$item->set_draw_as_radio(1);
	$item->signal_connect ( activate => sub
		{ ::EditFilter(undef,$WakeSchemes{$realScheme}->{wselectedfilter},undef, sub { $WakeSchemes{$realScheme}->{wselectedfilter} = $_[1]; $WakeSchemes{$realScheme}->{wselectedfiltertype} = 'filter';  SaveSchemes();});
		});
	$menu->append($item);
	if (my @SavedLists=::GetListOfSavedLists())
	{	my $submenu=Gtk2::Menu->new;
		my $list_cb=sub { $WakeSchemes{$realScheme}->{wselectedfilter} = $_[1]; $WakeSchemes{$realScheme}->{wselectedfiltertype} = 'staticlist';  SaveSchemes();};
		for my $list (@SavedLists)
		{	my $item = Gtk2::CheckMenuItem->new_with_label($list);
			$item->set_draw_as_radio(1);
			$item->set_active(1) if defined $::ListMode && $list eq $::ListMode;
			$item->signal_connect( activate =>  $list_cb, $list );
			$submenu->append($item);
		}
		my $sitem=Gtk2::MenuItem->new(_"Saved Lists");
		$sitem->set_submenu($submenu);
		$menu->prepend($sitem);
	}
	$menu->show_all;
	return $menu if $nopopup;
	my $event=Gtk2->get_current_event;
	my ($button,$pos)= $event->isa('Gtk2::Gdk::Event::Button') ? ($event->button,\&::menupos) : (0,undef);
	$menu->popup(undef,undef,$pos,undef,$button,$event->time);
}

1