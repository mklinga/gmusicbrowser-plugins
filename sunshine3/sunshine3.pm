# Gmusicbrowser: Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
# Sunshine3: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# TODO
#
# BUGS
#
=gmbplugin SUNSHINE3
name	Sunshine3
title	Sunshine3
=cut


package GMB::Plugin::SUNSHINE3;
my $VNUM = '3.00';

use strict;
use warnings;
use constant
{
	OPT	=> 'PLUGIN_SUNSHINE3_',
	SMALLESTFADE => 0.4,
	MAXALARMS => 5,
};

use utf8;

::SetDefaultOptions(OPT, UseDLog => 1, ShowContextMenu => 1, ShowAdvancedOptions => 0);

my %sunshine_button=
(	class	=> 'Layout::Button',
	stock	=>{passive => 'plugin-sunshine3', active => 'plugin-sunshine3-ON'},
	tip	=> " Sunshine v".$VNUM,
	click1 => sub {Launch(1);},
	click2 => sub {Launch(2);},
	click3 => sub {($::Options{OPT.'ShowContextMenu'})? LayoutButtonMenu() : Launch(3);},
	autoadd_type	=> 'button main',
	event => 'Sunshine3Status',
	state => sub { ($::Options{OPT.'Sunshine3IsOn'})? 'active' : 'passive' }
);

# Flags: f = finishonnext, a = addcurrent, t = create (t)imer, n = not in MS_dialog (for 'immediate')
my %SleepConditions = (
	'1_Queue' => {
		'label' => _('Queue empty'),
		CalcLength => 'my $l=0; $l += Songs::Get($_,qw/length/) for (@$::Queue); return $l;',
		IsFinished => 'return (!scalar@$::Queue)',
		Flags => 'fa'},
	'2_Albumchange' => {
		'label' => _('On albumchange'),
		CalcLength => 'my $l=0; my $IDs = AA::GetIDs(qw/album/,Songs::Get_gid($::SongID,qw/album/));Songs::SortList($IDs,$::Options{Sort});splice (@$IDs, 0, Songs::Get($::SongID,qw/track/));$l += Songs::Get($_,qw/length/) for (@$IDs); return $l;',
		IsFinished => 'return ($Alarm{$set}->{InitialAlbum} ne (join " ",Songs::Get($::SongID,qw/album_artist year album/)))',
		Flags => 'a'},
	'3_Count' => {
		'label' => _('After tracks'),
		OPT_setting => 'TrackCount',
		CalcLength => 'my @IDs = ::GetNextSongs($Alarm{$set}->{TrackCount}); splice (@IDs, 0,1);my $l=0;$l += Songs::Get($_,qw/length/) for (@IDs);return $l;',
		IsFinished => 'return ($Alarm{$set}->{PassedTracks} > $Alarm{$set}->{TrackCount})',
		Flags => 'fa'},
	'4_Time' => {
		'label' => _('After minutes') ,
		OPT_setting => 'TimeCount',
		CalcLength => 'return 60*$Alarm{$set}->{TimeCount}',
		IsFinished => 'return (time-$Alarm{$set}->{StartTime} >= ($Alarm{$set}->{TimeCount}*60))',
		Flags => 'ft'},
	'5_Immediate' => {
		'label' => _('Immediately'),
		CalcLength => 'return 0',
		IsFinished => 'return 1',
		Flags => 'n'},
);

# Some examples for additional commands:
# _('Clear Filter') => '::Select(filter => Filter->new)', _('Toggle Sort/Random') => '::ToggleSort()',
my %LaunchCommands = ( _('Play') => '::Play()', _('Pause') => '::Pause()', _('Nothing') => '',);
my %DelayCurves = ( _('Linear') => 1, _('Smooth') => 1.4, _('Smoothest') => 1.8, _('Steep') => 0.6,);
my %DelayPercs = (_('None') => 0, _('Small') => 0.25, _('Long') => 0.5);
my %ReqModes = ( _('Require all') => 'all', _('Require any') => 'any');
my %AlarmFields = (
	'FadeTo' => 0,
	'LaunchAt' => 0,
	'LaunchHour' => 22,
	'LaunchMin' => 0,
	'InitialCommand' => _('Nothing'),
	'UseFade' => 1,
	'DelayMode' => _('After minutes'),
	'FinishingCommand' => _('Nothing'),
	'TimeCount' => 45,
	'TrackCount' => 10,
	'DelayCurve' => 1,
	'DelayPerc' => 0,
	'ManualSleepConditions' => 0,
	'ManualReqCombo' => _('Require all'),
	'Name' => '',
	'FadeCurveCombo' => _('Linear'),
	'FadePercCombo' => _('None'));
# PN: Preset Name, LA: Launch at, IC: Initial command, VF: Volumefade, DM[E/M]: Delaymode [everything/minimal], FC: Finishing Command
# DA: Delay (advanced), MS : Multiple sleepconditions
my %Schemes = (
	_('Show everything') => { scheme => "PN|LA|IC|VF|DME|DA|FC|MS", specialset => undef },
	_('Basic sleepoptions') => { scheme =>  "VF|DME|FC", specialset => { LaunchAt => 0, InitialCommand => _('Nothing'), 'FinishingCommand' => 'Pause' } },
	_('Complex sleepoptions') => { scheme =>  "PN|LAVF|DME|DA|MS", specialset => { InitialCommand =>_('Nothing'), 'FinishingCommand' => 'Pause' } },
	_('Basic wakeoptions') => { scheme => "LA|VF|DMM", specialset => { InitialCommand => 'Play', 'FinishingCommand' => _('Nothing'), DelayMode => $SleepConditions{'4_Time'}->{label} }}
);

my %Alarm;
my $handle;
my $fadehandle;
my $oldID=-1;
my @FadeStack;

sub Start
{
	Dlog('Warming up Sunshine v'.$VNUM, '>');

	Layout::RegisterWidget('Sunshine3Button'=>\%sunshine_button);
	::Watch($handle, PlayingSong => \&SongChanged);
	$::Command{OPT.'LaunchAlarm'}=[\&Launch,_("PLUGIN/SUNSHINE3: Launch alarm"),_("Number of alarm (1..".MAXALARMS.")")];
	$::Options{OPT.'Sunshine3IsOn'} = 0;

	# Initialize some values for presets
	unless (defined $::Options{OPT.'preset'.(MAXALARMS).'Name'})
	{
		for my $set (reverse 1..MAXALARMS)
		{
			last if (defined $::Options{OPT.'preset'.$set.'Name'});
			$::Options{OPT.'preset'.$set.'NoDialogButton'} = 0;
			$::Options{OPT.'preset'.$set.'SchemeCombo'} = _('Show everything');

			for my $af (keys %AlarmFields) { $::Options{OPT.'preset'.$set.$af} = $AlarmFields{$af}; }
			for my $ms (keys %SleepConditions) {$::Options{OPT.'preset'.$set.'MS'.$ms} = 0;}

			$::Options{OPT.'preset'.$set.'Name'} = "Preset ".$set;
		}
	}
	# add OPT_settings in AlarmFields for simpifying setupping alarm
	for (keys %SleepConditions) { $AlarmFields{$SleepConditions{$_}->{OPT_setting}} = 0 if (defined $SleepConditions{$_}->{OPT_setting}); }
}

sub Stop
{
	Layout::RegisterWidget('Sunshine3Button');
	::UnWatch($handle,'PlayingSong') if ($handle);
	KillEverything();
}

sub prefbox
{
	my @f;
	my $frame = Gtk2::Frame->new(' Alarms ');
	for my $i (1..MAXALARMS)
	{
		my $entry = ::NewPrefEntry(OPT.'preset'.$i.'Name',$i.'.');
		my $check1 = ::NewPrefCheckButton(OPT.'preset'.$i.'NoDialog_Button','Launch without dialog');
		my $button1 = ::NewIconButton('gtk-properties',_('Properties'), sub {Launch($i,1); },undef);
		my $schemecombo = ::NewPrefCombo(OPT.'preset'.$i.'SchemeCombo',[sort keys %Schemes]);
		push @f, ::Hpack($entry,$schemecombo,$check1,$button1);
	}
	$frame->add(::Vpack(@f));
	my $contextCheck = ::NewPrefCheckButton(OPT.'ShowContextMenu','Show Context-menu on right-click');
	my $advancedCheck = ::NewPrefCheckButton(OPT.'ShowAdvancedOptions','Show advanced options');
	my $vbox=::Vpack($frame,$contextCheck,$advancedCheck);
	return $vbox;
}

sub SongChanged
{
	return if ($::SongID == $oldID);
	for (1..MAXALARMS) {
		$Alarm{$_}->{PassedTracks}++ if ($Alarm{$_}->{IsOn});
		FinishAlarm($_) if ($Alarm{$_}->{WaitingForNext});
	}
	CheckDelayConditions();

	return 1;
}

sub CheckDelayConditions
{
	my $s = shift;
	my @a = ($s)? ($s) : (1..MAXALARMS);

	for my $set (@a)
	{
		next if (($Alarm{$set}->{WaitingForNext}) or (!$Alarm{$set}->{IsOn}));

		my ($sleepnow, $finishonnext) = (0,0);
		my @SCs = split /\|/, $Alarm{$set}->{SC};
		my $req = shift @SCs;

		for my $SC (@SCs) {
			if (eval($SleepConditions{$SC}->{IsFinished}))	{
				$sleepnow++;
				$finishonnext++	if ($SleepConditions{$SC}->{Flags} =~ /f/);
			}
		}

		Dlog($sleepnow.' of '.(scalar@SCs).' conditions for alarm '.$set.'. \''.($Alarm{$set}->{Name}).'\' has finished (Required: '.$req.')');

		if (($req =~ /any/) and ($sleepnow > 0)){
			if ($sleepnow > $finishonnext) { FinishAlarm($set); }
			else { $Alarm{$set}->{WaitingForNext} = 1; }
		}
		elsif (($req =~ /all/) and ($sleepnow == (scalar@SCs))) {
			if ($finishonnext == 0) { FinishAlarm($set);}
			else { $Alarm{$set}->{WaitingForNext} = 1; }
		}
	}

	return 1;
}

sub FinishAlarm
{
	my $set = shift;
	return 0 unless ($Alarm{$set}->{IsOn});

	Dlog('Finishing alarm '.$set.'.\''.($Alarm{$set}->{Name}).'\'');
	DoCommand($Alarm{$set}->{FinishingCommand});
	KillAlarm($set);

	return 1;
}

sub Launch
{
	my ($set,$preflaunch);

	# First argument is hash when launching through keyboard command
	if (($_[0] =~ /HASH/) and ($_[1] =~ /^[1-MAXALARMS]$/)) { $set = $_[1] }
	else { ($set, $preflaunch) = @_; }

	# a little bit of error handling (never trust an user)
	unless ((defined $set) and ($set =~ /^[1-MAXALARMS]$/)) {
		Dlog('Bad argument in Launch(), replacing $set with number '.(MAXALARMS-1));
		$set = (MAXALARMS-1);
	}

	Dlog((($preflaunch)? '[Pref]' : '').'Launch('.$set.')');

	if (((!$preflaunch) and ($::Options{OPT.'preset'.$set.'NoDialog_Button'})) or (LaunchDialog($set,$preflaunch) eq 'ok'))
	{
		Dlog('Preparing to launch alarm '.$set);
		KillAlarm($set) if ((defined $Alarm{$set}) and ($Alarm{$set}->{IsOn}));
		unless (CreateNewAlarm($set)) { Dlog('CreateNewAlarm FAILED!'); return 0;}

		CheckDelayConditions();
		IsSunshineOn();
	}
	else { Dlog('...no Launch after all');}

	return 1;
}

sub LaunchDialog
{
	my ($set,$preflaunch) = @_;

	my $scheme = (defined $::Options{OPT.'preset'.$set.'SchemeCombo'})? $::Options{OPT.'preset'.$set.'SchemeCombo'} : _('Show everything');
	# for certain 'schemes' we want to set specific options even if they're not for user to decide (like InitialCommand = pause for 'basic wake' etc.)
	if (defined $Schemes{$scheme}->{specialset}){
		$::Options{OPT.'preset'.$set.$_} = ${$Schemes{$scheme}->{specialset}}{$_} for (keys %{$Schemes{$scheme}->{specialset}});
	}
	$scheme = $Schemes{$scheme}->{scheme}; # use schemestring from now on

	my $LaunchDialog = Gtk2::Dialog->new(_('Launch Sunshine'), undef, 'modal');
	my $cancelbutton = $LaunchDialog->add_button('Cancel', 'cancel');
	$LaunchDialog->add_button('Save',3) if ($preflaunch);
	$LaunchDialog->add_button('Launch', 'ok');
	$LaunchDialog->set_position('center-always');

	# PN: Preset Name
	my $PNentry = ::NewPrefEntry(OPT.'preset'.$set.'Name','Alarm\'s name:');
	my $PRESET_NAME = ($scheme =~ /PN/)? [$PNentry] : undef;

	# LA: Launch at
	my $check1 = ::NewPrefCheckButton(OPT.'preset'.$set.'LaunchAt','Launch at: ');
	my $spin1 = ::NewPrefSpinButton(OPT.'preset'.$set.'LaunchHour',0,24,wrap=>1);
	my $l1 = Gtk2::Label->new(_(':'));
	my $spin2 = ::NewPrefSpinButton(OPT.'preset'.$set.'LaunchMin',0,59,wrap=>1);
	my $labut1 = ::NewIconButton('gtk-refresh',undef,sub {
		my (undef,$M,$H,undef,undef,undef,undef,undef,undef) = localtime(time);
		$spin1->set_value($H); $spin2->set_value($M);
		$::Options{OPT.'preset'.$set.'LaunchHour'} = $H;
		$::Options{OPT.'preset'.$set.'LaunchMin'} = $M;
		},undef);
	my $LAUNCH_AT = ($scheme =~ /LA/)? [$check1,$spin1,$l1,$spin2,$labut1] : undef;

	# IC: Initial command
	my $l2 = Gtk2::Label->new('Initial command: ');
	my $combo1 = ::NewPrefCombo(OPT.'preset'.$set.'InitialCommand',[sort keys %LaunchCommands]);
	my $INITIAL_COMMAND = ($scheme =~ /IC/)? [$l2,$combo1] : undef;

	# VF: Volume fade
	my $check2 = ::NewPrefCheckButton(OPT.'preset'.$set.'UseFade','Fade volume to');
	my $spin3 = ::NewPrefSpinButton(OPT.'preset'.$set.'FadeTo',0,100);
	my $but1 = ::NewIconButton('gtk-refresh',undef,sub { $::Options{OPT.'preset'.$set.'FadeTo'} = ::GetVol; $spin3->set_value($::Options{OPT.'preset'.$set.'FadeTo'});}	,undef);
	my $VOLUME_FADE = ($scheme =~ /VF/)? [$check2,$spin3,$but1] : undef;

	# DM: Delaymode
	my $l3 = ($scheme =~ /DME/)? Gtk2::Label->new('Delaymode') : Gtk2::Label->new('Minutes to fade');
	my $spin4 = ::NewPrefSpinButton(OPT.'preset'.$set.'DelayModeEntry',1,720, cb => sub {
			my ($scitem) = grep {($::Options{OPT.'preset'.$set.'DelayMode'} =~ /^$SleepConditions{$_}->{label}/) } (keys %SleepConditions);
			$::Options{OPT.'preset'.$set.$SleepConditions{$scitem}->{OPT_setting}} = $::Options{OPT.'preset'.$set.'DelayModeEntry'} if (exists $SleepConditions{$scitem}->{OPT_setting});
	});
	my $refr = sub {
		my ($scitem) = grep {($::Options{OPT.'preset'.$set.'DelayMode'} =~ /^$SleepConditions{$_}->{label}/) } (keys %SleepConditions);
		$spin4->set_value($::Options{OPT.'preset'.$set.$SleepConditions{$scitem}->{OPT_setting}}) if (exists $SleepConditions{$scitem}->{OPT_setting});
		$spin4->set_sensitive((defined $SleepConditions{$scitem}->{OPT_setting})? 1 : 0);
	};
	my @p = map { $SleepConditions{$_}->{label} } (sort keys %SleepConditions);
	my $combo2 = ::NewPrefCombo(OPT.'preset'.$set.'DelayMode', \@p, cb => $refr);
	my $DELAY_MODE = ($scheme =~ /DM/)? (($scheme =~ /DME/)? [$l3,$combo2,$spin4] : [$l3,$spin4]) : undef;

	# FC: Finishing command
	my $l4 = Gtk2::Label->new('Finishing command: ');
	my $combo5 = ::NewPrefCombo(OPT.'preset'.$set.'FinishingCommand',[sort keys %LaunchCommands]);
	my $FINISHING_COMMAND = ($scheme =~ /FC/)? [$l4,$combo5] : undef;


	# Advanced Options
	# We can't allow manual sleepconditions if they're not visible!
	$::Options{OPT.'preset'.$set.'ManualSleepConditions'} = 0 unless (($::Options{OPT.'ShowAdvancedOptions'}) and ($scheme =~ /MS/));

	# DA: Delay (advanced)
	my $combo3 = ::NewPrefCombo(OPT.'preset'.$set.'FadeCurveCombo',[sort keys %DelayCurves], text => 'Curve: ', cb => sub { $::Options{OPT.'preset'.$set.'DelayCurve'} = $DelayCurves{$::Options{OPT.'preset'.$set.'FadeCurveCombo'}}});
	my $combo4 = ::NewPrefCombo(OPT.'preset'.$set.'FadePercCombo',[sort keys %DelayPercs], text => 'Delay: ', cb => sub { $::Options{OPT.'preset'.$set.'DelayPerc'} = $DelayPercs{$::Options{OPT.'preset'.$set.'FadePercCombo'}}});
	my $DELAY_ADVANCED = ($scheme =~ /DA/)? [$combo3,$combo4] : undef;

	# MS: Manual Sleepconditions
	my $mscombo = ::NewPrefCombo(OPT.'preset'.$set.'ManualReqCombo',[sort keys %ReqModes]);
	my @cs;
	for (sort keys %SleepConditions) {
		if (defined $SleepConditions{$_}->{OPT_setting}) {
			push @cs, [::NewPrefCheckButton(OPT.'preset'.$set.'MS'.$_,$SleepConditions{$_}->{label}),::NewPrefSpinButton(OPT.'preset'.$set.$SleepConditions{$_}->{OPT_setting},1,720)];
		}
		else{
			push @cs, ::NewPrefCheckButton(OPT.'preset'.$set.'MS'.$_,$SleepConditions{$_}->{label});
		}
	}
	my $mssens = sub {
		my $s = ($::Options{OPT.'preset'.$set.'ManualSleepConditions'})? 1 : 0;
		for my $c (@cs){
			if(ref($c) eq 'ARRAY'){$_->set_sensitive($s) for (@{$c});}
			else {$c->set_sensitive($s);}
		}
		$mscombo->set_sensitive($s);
		$combo2->set_sensitive(!$s);
		$spin4->set_sensitive(!$s);
	};
	my $mscheck1 = ::NewPrefCheckButton(OPT.'preset'.$set.'ManualSleepConditions','Use custom delayconditions', cb => $mssens);
	my @MANUAL_SLEEPCONDITIONS = ($scheme =~ /MS/)? [$mscheck1,$mscombo,@cs] : undef;

	my $vbox = ::Vpack($PRESET_NAME,$LAUNCH_AT,$INITIAL_COMMAND,$VOLUME_FADE,$DELAY_MODE,$FINISHING_COMMAND);
	my $vbox2 = ::Vpack($DELAY_ADVANCED,\@MANUAL_SLEEPCONDITIONS);
	&$refr;
	&$mssens if (($::Options{OPT.'ShowAdvancedOptions'}) and ($scheme =~ /MS/));

	my $dl = $vbox;
	# if we have advanced options, we'll show notebook containing 'basic' and 'advanced'
	if (($::Options{OPT.'ShowAdvancedOptions'}) and ($scheme =~ /MS|DA/))
	{
		$dl = Gtk2::Notebook->new();
		$dl->append_page($vbox,'Basic');
		$dl->append_page($vbox2,'Advanced');
	}
	else # if advanced options are hidden, we'll disable 'multiple sleepconditions' in any case
	{
		$::Options{OPT.'preset'.$set.'ManualSleepConditions'} = 0;
	}

	$LaunchDialog->get_content_area()->add($dl);
	$LaunchDialog->set_default_response ('cancel');
	$LaunchDialog->show_all;
	$LaunchDialog->set_focus($cancelbutton);

	my $response = $LaunchDialog->run;

	$LaunchDialog->destroy();

	return $response;
}

sub DoCommand
{
	my $cmd = shift;
	return 0 unless (defined $LaunchCommands{$cmd});

	eval($LaunchCommands{$cmd});
	if ($@) { Dlog('LaunchCommand\'s eval produced some errors - retreating as gracefully as possible.'); return 0;}

	return 1;
}

sub GetNextTime
{
	my $timestring = shift;
	my $Now=time;
	my (undef,$cMin,$cHour,$cMday,$cMon,$cYear,undef,undef,undef) = localtime($Now);

	return 0 unless ($timestring =~ /^(\d{1,2})\:(\d{1,2})$/);
	my $Next = ::mktime(0,$2,$1,$cMday,$cMon,$cYear);
	$Next += (24*60*60) if ($Next < $Now); # if time we got is smaller than 'now', the next occurance is tomorrow

	return ($Next-$Now);
}

sub CalculateDelayTime
{
	my $set = shift;

	unless (defined $Alarm{$set}->{SC}) {
		Dlog('Something is not right in CalculateDelayTime - there seems to be no sleepcondition available!');
		return 0;
	}

	my @SCs = split /\|/, $Alarm{$set}->{SC};
	my $req = shift @SCs;

	my $final;
	for (@SCs)
	{
		my $length = eval($SleepConditions{$_}->{CalcLength});
		if ($@) { Dlog('Errors in eval @ CalculateDelayTime! SC: '.$_); next;}
		$length += (Songs::Get($::SongID,'length')-($::PlayTime || 0)) if ($SleepConditions{$_}->{Flags} =~ /a/);

		$final = $length if (not defined $final);
		$final = $length if (($req =~ /any/) and ($length < $final));
		$final = $length if (($req =~ /all/) and ($length > $final));
	}

	return ($final || 0);
}

sub CreateFade
{
	my ($sec,$to,$fadecurve,$fadeperc) = @_;
	my $currentVol = ::GetVol();
	$fadecurve ||= 1;
	$fadeperc ||= 0;
	my $delta = abs($to-$currentVol);
	my $r = ($to > $currentVol)? (1) : (-1);
	return 1 unless ($delta); #we have no reason to send 'fail' if there's nothing to fade, just skip fading as successful

	# Fadestack consists of two arrays (in an array): [0] relative time for next fade, and [1] amount of volume to change
	@FadeStack = ();
	if (defined $fadehandle) { Glib::Source->remove($fadehandle); Dlog('Stopped previous fade before finishing it'); }
	Dlog('Creating new Fade! Delta: '.$delta.' ('.$currentVol.' -> '.$to.'), Curve: '.$fadecurve.', Delay: '.$fadeperc);
	Dlog('Smallest allowed fade interval: '.SMALLESTFADE);

	# set fade delay here, if wanted
	if ($fadeperc) {
		my $origsec = $sec;
		$sec *= (1-$fadeperc);
		push @{$FadeStack[0]}, ($origsec-$sec);
		push @{$FadeStack[1]}, $currentVol; # no volumechange on this one
		Dlog('Due to '.$fadeperc.' FadeDelay we\'re fading in: '.$sec.' seconds (original was '.$origsec.')');
	}
	else {Dlog('Fading in: '.$sec.' seconds');}

	Dlog('** Starting FadeCurve calculations **');
	my ($swing,$previous,$prevvol) = (0,0,$currentVol);
	for (1..$delta)
	{
		# Calculate time 'x' for next volumechange
		my $x = (($_/$delta) ** (1/$fadecurve))*$sec;

		# If position is too soon, we'll skip it and add more volume next time
		if (($x-$previous) < SMALLESTFADE) { $swing += 1; }
		else
		{
			push @{$FadeStack[0]}, ($x-$previous); # we want relative time in stack
			push @{$FadeStack[1]}, $prevvol+$r*(1+$swing); # volume values are absolute (0..100)
			Dlog($_.' ('.($prevvol+$r*(1+$swing)).') = '.($x-$previous).' ('.$x.')');
			$prevvol += $r*(1+$swing);
			$previous = $x;
			$swing = 0;
		}
	}

	# if there's still some need for change, we'll add it to last item
	${$FadeStack[1]}[scalar@{$FadeStack[1]}-1] += $r*$swing if ($swing);

	return Fade(1);
}

sub Fade
{
	my $init = shift;

	if (!$init)
	{
		my $CurVol = ::GetVol();
		my $ToVol = (scalar@{$FadeStack[1]})? (shift @{$FadeStack[1]}) : $CurVol;
		::UpdateVol($ToVol) if ($CurVol != $ToVol);
	}

	KillFade((scalar@{$FadeStack[0]})? 1 : undef);
	return 0 unless (scalar@{$FadeStack[0]});

	my $next = shift @{$FadeStack[0]};
	$fadehandle = Glib::Timeout->add($next*1000, sub { return Fade(); },1);

	return 1;
}

sub KillFade
{
	my $silent = shift;

	Glib::Source->remove($fadehandle) if (defined $fadehandle);
	$fadehandle = undef;

	unless ($silent){
		@FadeStack = ();
		Dlog('Killed volumefade');
		IsSunshineOn();
	}

	return 1;
}

sub CreateNewAlarm
{
	my ($set,$nosetup) = @_;

	unless ($nosetup)
	{

		Dlog('Setting properties for alarm '.$set);
		for (keys %AlarmFields) { $Alarm{$set}->{$_} = $::Options{OPT.'preset'.$set.$_}; }
		$Alarm{$set}->{SC} = GetSCString($set);
		$Alarm{$set}->{DelayTime} = CalculateDelayTime($set);
	}

	Dlog('Creating new alarm '.$set.'. \''.$Alarm{$set}->{Name}.'\'');
	if ($Alarm{$set}->{LaunchAt}) {
		my $timetolaunch = GetNextTime($Alarm{$set}->{LaunchHour}.':'.$Alarm{$set}->{LaunchMin});
		$Alarm{$set}->{alarmhandle} = Glib::Timeout->add($timetolaunch*1000,sub
			{
				CreateNewAlarm($set,1) unless ($Alarm{$set}->{IsON});
				IsSunshineOn();
				return 0;
		},1);
		$Alarm{$set}->{LaunchAt} = 0;
		$Alarm{$set}->{IsOn} = 0;
		$Alarm{$set}->{IsWaiting} = 1;
		Dlog('Waiting for ['.sprintf("%.2d\:%.2d",$Alarm{$set}->{LaunchHour},$Alarm{$set}->{LaunchMin}).'] to launch Wake-alarm (in '.$timetolaunch.' seconds)');
		return 2; # we'll be back after a while
	}

	if ($Alarm{$set}->{UseFade}) {
		if ($Alarm{$set}->{DelayTime}) {
			unless (CreateFade($Alarm{$set}->{DelayTime},$Alarm{$set}->{FadeTo},$Alarm{$set}->{DelayCurve},$Alarm{$set}->{DelayPerc})) {
				Dlog('Error in CreateFade! Abandoning alarm creation.');
				return 0;
			}
		}
		else { 
			Dlog('No time to fade! Setting volume ('.$Alarm{$set}->{FadeTo}.') immediately'); 
			::UpdateVol($Alarm{$set}->{FadeTo}) if (::GetVol() != $Alarm{$set}->{FadeTo});
		}
	}

	$Alarm{$set}->{IsWaiting} = 0;
	$Alarm{$set}->{IsOn} = 1;
	$Alarm{$set}->{StartTime} = time;
	$Alarm{$set}->{InitialAlbum} = join " ", Songs::Get($::SongID,qw/album_artist year album/);
	$Alarm{$set}->{PassedTracks} = ($::TogPlay)? -1 : 0; # don't count  current song if it's already playing

	DoCommand($Alarm{$set}->{InitialCommand}) unless ($LaunchCommands{$Alarm{$set}->{InitialCommand}} eq '');

	# We only create sleep-timer (alarmhandle) if needed
	my @scs = split /\|/, $Alarm{$set}->{SC};
	shift @scs;
	for (@scs)
	{
		next unless ($SleepConditions{$_}->{Flags} =~ /t/);
		if ($Alarm{$set}->{TimeCount} > $Alarm{$set}->{DelayTime}) { 
			Dlog('Skip creating alarmhandle for Time, since alarm seems to finish before it anyway'); 
			next; 
		}

		Dlog('Creating alarmhandle for Time ('.($Alarm{$set}->{TimeCount}*60).' sec)');
		$Alarm{$set}->{alarmhandle} = Glib::Timeout->add($Alarm{$set}->{TimeCount}*60*1000, sub {
				Dlog('Alarm '.$set.'. '.$Alarm{$set}->{Name}.' has finished its TimeCount');
				CheckDelayConditions();
				return 0;
			},1);
	}

	return 1;
}

sub GetSCString
{
	my $set = shift;
	my $string = (($Alarm{$set}->{ManualSleepConditions}) and ($ReqModes{$Alarm{$set}->{'ManualReqCombo'}} =~ /any/))? 'any' : 'all';

	for (keys %SleepConditions) {
			$string .= '|'.$_ if ((!$Alarm{$set}->{ManualSleepConditions}) and ($::Options{OPT.'preset'.$set.'DelayMode'} =~ /^$SleepConditions{$_}->{label}/));
			$string .= '|'.$_ if (($Alarm{$set}->{ManualSleepConditions}) and ($::Options{OPT.'preset'.$set.'MS'.$_}));
	}
	return (($string =~ /^(any|all)$/)? 'any|'.(keys %SleepConditions)[0] : $string);
}

# KillAlarm doesn't stop ongoing fades
sub KillAlarm
{
	my @kill = @_;
	@kill = (1..MAXALARMS) if ((scalar@kill) and ($kill[0] < 0));

	for my $set (@kill)
	{
		next unless ((defined $Alarm{$set}) and ($Alarm{$set}->{IsOn}));
		Dlog('Killing alarm no: '.$set.'. \''.$Alarm{$set}->{Name}.'\'');
		Glib::Source->remove($Alarm{$set}->{alarmhandle}) if (defined $Alarm{$set}->{alarmhandle});
		$Alarm{$set} = undef;
	}

	IsSunshineOn();
	return 1;
}

sub KillEverything
{
	return ((KillAlarm(-1)) and (KillFade()))? 1 : 0;
}

sub IsSunshineOn
{
	my $ON = 0;

	$ON = 1 if ((defined $fadehandle) and (scalar@FadeStack));
	unless ($ON) { for (1..MAXALARMS) { if (($Alarm{$_}->{IsOn}) or ($Alarm{$_}->{IsWaiting})) { $ON = 1; last;} } }

	if ($::Options{OPT.'Sunshine3IsOn'} != $ON) {
		$::Options{OPT.'Sunshine3IsOn'} = $ON;
		Dlog('SunshineStatus has changed to : '.(($ON)? 'ON' : 'OFF'));
		::HasChanged('Sunshine3Status');
	}

	return $ON;
}

sub LayoutButtonMenu
{
	my $menu = Gtk2::Menu->new;

	#helper method
	my $append=sub
	 {	my ($menu,$set)=@_;
		my $item = Gtk2::CheckMenuItem->new_with_label($::Options{OPT.'preset'.$set.'Name'});
		my $true = ($Alarm{$set}->{IsOn})? 1 : 0;
		$item->set_active($true);
		$item->signal_connect (activate => sub { Launch($set);});
		$menu->append($item);
	 };

	#Launch / menu
	my $sleepmenu= Gtk2::Menu->new;
	my $launchmenu = Gtk2::MenuItem->new("Launch");

	$append->($sleepmenu,$_) for (1..MAXALARMS);
	$launchmenu->set_submenu($sleepmenu);
	$menu->append($launchmenu);

	# Kill single alarm (if we have one)
	my @alarms = grep { $Alarm{$_}->{IsOn}} (1..MAXALARMS);

	if (scalar@alarms)
	{
		my $activemenu= Gtk2::Menu->new;
		my $aitem = Gtk2::MenuItem->new('Kill Alarm');

		my $append2=sub
		{
			my ($menu,$set)=@_;
			my $item = Gtk2::MenuItem->new_with_label($::Options{OPT.'preset'.$set.'Name'});
			$item->signal_connect (activate => sub { KillAlarm($set);});
			$menu->append($item);
		 };

		$append2->($activemenu,$_) for (@alarms);
		$aitem->set_submenu($activemenu);
		$menu->append($aitem);
	}

	$menu->append(Gtk2::SeparatorMenuItem->new);
	# Stop volumefade (if it's on)
	if ((defined $fadehandle) and (scalar@FadeStack))
	{
		my $killfade = Gtk2::MenuItem->new('Stop Volumefade');
		$killfade->signal_connect(activate => \&KillFade);
		$menu->append($killfade);
	}

	#Stop Everything
	my $stopitem = Gtk2::MenuItem->new('Stop Everything');
	$stopitem->signal_connect (activate => \&KillEverything);
	$menu->append($stopitem);

	$menu->show_all;
	my $event=Gtk2->get_current_event;
	my ($button,$pos)= $event->isa('Gtk2::Gdk::Event::Button') ? ($event->button,\&::menupos) : (0,undef);
	$menu->popup(undef,undef,$pos,undef,$button,$event->time);
}

sub Dlog
{
	my ($t,$method) = @_;
	$method ||= '>>';

	return 0 unless ($::Options{OPT.'UseDLog'});

	my $DlogFile = $::HomeDir.'sunshine3.log';
	my $content = '['.localtime(time).'] '.$t."\n";

	open my $fh,$method,$DlogFile or warn "Error opening '$DlogFile' for writing : $!\n";
	print $fh $content   or warn "Error writing to '$DlogFile' : $!\n";
	close $fh;

	return 1;


}

1
