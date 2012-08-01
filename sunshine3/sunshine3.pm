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

::SetDefaultOptions(OPT, LaunchAt => 0, LaunchHour => 19, LaunchMin => 0, InitialCommand => _('Nothing'), FinishingCommand => _('Nothing'),
	FadeTo => 0, DelayMode => _('After minutes'), FadeCurveCombo => _('Linear'), DelayCurve => 1, FadePercCombo => _('None'), DelayPerc => 0,
	UseDLog => 1, TimeCount => 30, TrackCount => 8, ManualReqCombo => _('Require all'), ShowContextMenu => 1);

my %dayvalues= ( Mon => 1, Tue => 2,Wed => 3,Thu => 4,Fri => 5,Sat => 6,Sun => 0);
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
		Flags => 't'},
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
my @AlarmFields = ('FadeTo', 'LaunchAt','LaunchHour','LaunchMin','InitialCommand','UseFade','DelayMode','FinishingCommand', 'TimeCount','TrackCount',
	'DelayCurve','DelayPerc','ManualSleepConditions','ManualReqCombo','Name', 'FadeCurveCombo','FadePercCombo');

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
	unless (defined $::Options{OPT.'preset1Name'})
	{
		for (1..MAXALARMS)
		{
			$::Options{OPT.'preset'.$_.'Name'} = "Preset ".$_;
			$::Options{OPT.'NoDialogButton'.$_} = 0;
			$::Options{OPT.'ShowAdvanced'.$_} = 0;
			$::Options{OPT.'SchemeCombo'.$_} = _('Show everything');
		}
	}
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
	for my $i (1..MAXALARMS)
	{
		my $title = ($i < 4)? ('Button '.$i) : ('Preset '.$i); 
		push @f, Gtk2::Frame->new($title);
		my $check1 = ::NewPrefCheckButton(OPT.'NoDialog_Button'.$i,'Launch immediately');
		my $check2 = ::NewPrefCheckButton(OPT.'ShowAdvanced'.$i,'Show advanced options');
		my $button1 = ::NewIconButton('gtk-apply',_('Preferences'), sub {Launch($i,1); },undef);
		my $schemecombo = ::NewPrefCombo(OPT.'SchemeCombo'.$i,[sort keys %Schemes]);
		$f[$i-1]->add(::Hpack($schemecombo,$check1,$check2,$button1));
	}

	my $contextCheck = ::NewPrefCheckButton(OPT.'ShowContextMenu','Show Context-menu on right-click');
	my $vbox=::Vpack(@f,$contextCheck);
	return $vbox;
}

sub SongChanged
{
	return if ($::SongID == $oldID);
	for (1..MAXALARMS) {$Alarm{$_}->{PassedTracks}++ if ($Alarm{$_}->{IsOn});}
	CheckDelayConditions();

	return 1;
}

sub CheckDelayConditions
{
	my $s = shift;
	my @a = ($s)? ($s) : (1..MAXALARMS);

	for my $set (@a)
	{
		next unless ($Alarm{$set}->{IsOn});

		if ($Alarm{$set}->{WaitingForNext}) { FinishAlarm($set); next; }

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
			if ($finishonnext == 0) { FinishAlarm{$set};}
			else { $Alarm{$set}->{WaitingForNext} = 1; }
		}
	}
	
	return 1;
}

sub FinishAlarm
{
	my $set = shift;

	return 0 unless ((defined $set) and ($Alarm{$set}->{IsOn}));

	Dlog('Finishing alarm '.$set.'. '.($Alarm{$set}->{Name}));
	DoCommand($Alarm{$set}->{FinishingCommand});
	KillAlarm($set);

	return 1;
}

sub Launch
{
	my ($set,$preflaunch);

	if (($_[0] =~ /HASH/) and ($_[1] =~ /^[1-MAXALARMS]$/)) { $set = $_[1] } 
	else { ($set, $preflaunch) = @_; }

	# a little bit of error handling (never trust an user)
	unless ((defined $set) and ($set =~ /^[1-MAXALARMS]$/)) {
		Dlog('Bad argument in Launch(), replacing $set with number '.(MAXALARMS-1));
		$set = (MAXALARMS-1);
	}

	Dlog((($preflaunch)? '[Pref]' : '').'Launch('.$set.')');

	if (((!$preflaunch) and ($::Options{OPT.'NoDialog_Button'.$set})) or (LaunchDialog($set,$preflaunch) eq 'ok'))
	{
		Dlog('Preparing to launch alarm '.$set);
		KillAlarm($set) if ((defined $Alarm{$set}) and ($Alarm{$set}->{IsOn}));
		#copy values from dialog to $Alarm{$set}
		unless (SetupNewAlarm($set)) { Dlog('SetupNewAlarm FAILED!'); return 0;}
		# launch the actual alarm
		unless (CreateNewAlarm($set)) { Dlog('CreateNewAlarm FAILED!'); return 0;}
	}
	else { Dlog('...no Launch after all');}

	CheckDelayConditions();
	IsSunshineOn();

	return 1;
}

sub SavePreset
{
	my $set = shift;

	for (@AlarmFields) {
		$::Options{OPT.'preset'.$set.$_} = $::Options{OPT.$_} if (defined $::Options{OPT.$_} );
	}
	for (keys %SleepConditions){
		$::Options{OPT.'preset'.$set.'MS'.$_} = $::Options{OPT.'MS'.$_} if (defined $::Options{OPT.'MS'.$_} );
	}

	return 1;
}

sub LoadPreset
{
	my $set = shift;

	for (@AlarmFields) {
		$::Options{OPT.$_} = $::Options{OPT.'preset'.$set.$_} if (defined $::Options{OPT.'preset'.$set.$_});
	}
	for (keys %SleepConditions){
		$::Options{OPT.'MS'.$_}  = $::Options{OPT.'preset'.$set.'MS'.$_} if (defined $::Options{OPT.'preset'.$set.'MS'.$_});
	}

	return 1;
}

sub SetSchemeSpecialSettings
{
	my $scheme = shift;

	return 0 unless (defined $Schemes{$scheme}->{specialset});
	
	for (keys %{$Schemes{$scheme}->{specialset}})
	{
		$::Options{OPT.$_} = ${$Schemes{$scheme}->{specialset}}{$_};
		Dlog('Specialsetup ['.$scheme.']: '.$_.' => '.${$Schemes{$scheme}->{specialset}}{$_});
	}

	return 1;
}

sub LaunchDialog
{
	my ($set,$preflaunch) = @_;

	LoadPreset($set);

	my $scheme = (defined $::Options{OPT.'SchemeCombo'.$set})? $::Options{OPT.'SchemeCombo'.$set} : _('Show everything');
	# for certain 'schemes' we want to set specific options even if they're not for user to decide (like InitialCommand = pause for 'basic wake' etc.)
	SetSchemeSpecialSettings($scheme);
	$scheme = $Schemes{$scheme}->{scheme}; # use schemestring from now on

	my $LaunchDialog = Gtk2::Dialog->new(_('Launch Sunshine'), undef, 'modal');
	my $cancelbutton = $LaunchDialog->add_button('Cancel', 'cancel');
	$LaunchDialog->add_button('Save',3) if ($preflaunch);
	$LaunchDialog->add_button('Launch', 'ok');
	$LaunchDialog->set_position('center-always');

	# PN: Preset Name
	my $PNentry = ::NewPrefEntry(OPT.'Name','Alarm\'s name:');
	my $PRESET_NAME = ($scheme =~ /PN/)? [$PNentry] : undef;

	# LA: Launch at
	my $check1 = ::NewPrefCheckButton(OPT.'LaunchAt','Launch at: ');
	my $spin1 = ::NewPrefSpinButton(OPT.'LaunchHour',0,24,wrap=>1);
	my $l1 = Gtk2::Label->new(_(':'));
	my $spin2 = ::NewPrefSpinButton(OPT.'LaunchMin',0,59,wrap=>1);
	my $labut1 = ::NewIconButton('gtk-refresh',undef,sub {
		my (undef,$M,$H,undef,undef,undef,undef,undef,undef) = localtime(time);
		$spin1->set_value($H); $spin2->set_value($M);
		$::Options{OPT.'LaunchHour'} = $H;
		$::Options{OPT.'LaunchMin'} = $M;
		},undef);
	my $LAUNCH_AT = ($scheme =~ /LA/)? [$check1,$spin1,$l1,$spin2,$labut1] : undef;
	
	# IC: Initial command
	my $l2 = Gtk2::Label->new('Initial command: ');
	my $combo1 = ::NewPrefCombo(OPT.'InitialCommand',[sort keys %LaunchCommands]);
	my $INITIAL_COMMAND = ($scheme =~ /IC/)? [$l2,$combo1] : undef;

	# VF: Volume fade
	my $check2 = ::NewPrefCheckButton(OPT.'UseFade','Fade volume to');
	my $spin3 = ::NewPrefSpinButton(OPT.'FadeTo',0,100);
	my $but1 = ::NewIconButton('gtk-refresh',undef,sub { $::Options{OPT.'FadeTo'} = ::GetVol; $spin3->set_value($::Options{OPT.'FadeTo'});}	,undef);
	my $VOLUME_FADE = ($scheme =~ /VF/)? [$check2,$spin3,$but1] : undef;

	# DM: Delaymode
	my $l3 = ($scheme =~ /DME/)? Gtk2::Label->new('Delaymode') : Gtk2::Label->new('Minutes to fade');
	my $spin4 = ::NewPrefSpinButton(OPT.'DelayModeEntry',1,720, cb => sub {
			my ($scitem) = grep {($::Options{OPT.'DelayMode'} =~ /^$SleepConditions{$_}->{label}/) } (keys %SleepConditions);
			$::Options{OPT.$SleepConditions{$scitem}->{OPT_setting}} = $::Options{OPT.'DelayModeEntry'} if (exists $SleepConditions{$scitem}->{OPT_setting});
	});
	my $refr = sub {
		my ($scitem) = grep {($::Options{OPT.'DelayMode'} =~ /^$SleepConditions{$_}->{label}/) } (keys %SleepConditions);
		$spin4->set_value($::Options{OPT.$SleepConditions{$scitem}->{OPT_setting}}) if (exists $SleepConditions{$scitem}->{OPT_setting});
		$spin4->set_sensitive((defined $SleepConditions{$scitem}->{OPT_setting})? 1 : 0);
	};
	my @p = map { $SleepConditions{$_}->{label} } (sort keys %SleepConditions);
	my $combo2 = ::NewPrefCombo(OPT.'DelayMode', \@p, cb => $refr);
	my $DELAY_MODE = ($scheme =~ /DM/)? (($scheme =~ /DME/)? [$l3,$combo2,$spin4] : [$l3,$spin4]) : undef;

	# FC: Finishing command
	my $l4 = Gtk2::Label->new('Finishing command: ');
	my $combo5 = ::NewPrefCombo(OPT.'FinishingCommand',[sort keys %LaunchCommands]);
	my $FINISHING_COMMAND = ($scheme =~ /FC/)? [$l4,$combo5] : undef;


	# Advanced Options

	# We can't allow manual sleepconditions if they're not visible!
	$::Options{OPT.'ManualSleepConditions'} = 0 unless (($::Options{OPT.'ShowAdvanced'.$set}) and ($scheme =~ /MS/));

	# DA: Delay (advanced)
	my $combo3 = ::NewPrefCombo(OPT.'FadeCurveCombo',[sort keys %DelayCurves], text => 'Curve: ', cb => sub { $::Options{OPT.'DelayCurve'} = $DelayCurves{$::Options{OPT.'FadeCurveCombo'}}});
	my $combo4 = ::NewPrefCombo(OPT.'FadePercCombo',[sort keys %DelayPercs], text => 'Delay: ', cb => sub { $::Options{OPT.'DelayPerc'} = $DelayPercs{$::Options{OPT.'FadePercCombo'}}});
	my $DELAY_ADVANCED = ($scheme =~ /DA/)? [$combo3,$combo4] : undef;
	
	# MS: Manual Sleepconditions
	my $mscombo = ::NewPrefCombo(OPT.'ManualReqCombo',[_('Require all'),_('Require any')]);
	my @cs;
	for (sort keys %SleepConditions) {
		if (defined $SleepConditions{$_}->{OPT_setting}) {
			push @cs, [::NewPrefCheckButton(OPT.'MS'.$_,$SleepConditions{$_}->{label}),::NewPrefSpinButton(OPT.'MS'.$SleepConditions{$_}->{OPT_setting},1,720)];
		}
		else{
			push @cs, ::NewPrefCheckButton(OPT.'MS'.$_,$SleepConditions{$_}->{label});
		}
	}
	my $mssens = sub {
		my $s = ($::Options{OPT.'ManualSleepConditions'})? 1 : 0;
		for my $c (@cs){
			if(ref($c) eq 'ARRAY'){$_->set_sensitive($s) for (@{$c});}
			else {$c->set_sensitive($s);}
		}
		$mscombo->set_sensitive($s);
		$combo2->set_sensitive(!$s);
		$spin4->set_sensitive(!$s);
	};
	my $mscheck1 = ::NewPrefCheckButton(OPT.'ManualSleepConditions','Use custom delayconditions', cb => $mssens);
	my @MANUAL_SLEEPCONDITIONS = ($scheme =~ /MS/)? [$mscheck1,$mscombo,@cs] : undef;

	my $vbox = ::Vpack($PRESET_NAME,$LAUNCH_AT,$INITIAL_COMMAND,$VOLUME_FADE,$DELAY_MODE,$FINISHING_COMMAND);
	my $vbox2 = ::Vpack($DELAY_ADVANCED,\@MANUAL_SLEEPCONDITIONS);
	&$refr;
	&$mssens if (($::Options{OPT.'ShowAdvanced'.$set}) and ($scheme =~ /MS/)); 

	my $dl = $vbox;
	# if we have advanced options, we'll show notebook containing 'basic' and 'advanced'
	if (($::Options{OPT.'ShowAdvanced'.$set}) and ($scheme =~ /MS|DA/))
	{
		$dl =Gtk2::Notebook->new();
		$dl->append_page($vbox,'Basic');
		$dl->append_page($vbox2,'Advanced');
	}
	else # if advanced options are hidden, we'll disable 'multiple sleepconditions' in any case
	{ 
		$::Options{OPT.'ManualSleepConditions'} = 0;
	}

	$LaunchDialog->get_content_area()->add($dl);
	$LaunchDialog->set_default_response ('cancel');
	$LaunchDialog->show_all;
	$LaunchDialog->set_focus($cancelbutton);

	my $response = $LaunchDialog->run;
	
	$LaunchDialog->destroy();
	SavePreset($set) if ($response ne 'cancel');

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
		my $Monthday = $cMday+($Weekday-$cWeekday);
		my $NextTime = ::mktime(0,$Min,$Hour,$Monthday,$cMon,$cYear);
		$NextTime += (7*24*60*60) if ($NextTime < $Now); #if time we got is smaller than 'now', then next occurance is a week later

		$Next = $NextTime if ((!$Next) or ($Next > $NextTime));
	}

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

	return 1 unless ($delta); #we have no reason to send 'fail' if there's nothing to fade, just skip it as successful

	# Fadestack consists of two arrays (in an array): [0] relative time for next fade, and [1] amount of volume to change
	@FadeStack = ();
	if (defined $fadehandle) { Glib::Source->remove($fadehandle); Dlog('Stopped previous fade before finishing it'); }
	Dlog('Creating new Fade! Delta: '.$delta.', Curve: '.$fadecurve.', Delay: '.$fadeperc);
	Dlog('Smallest allowed fade interval: '.SMALLESTFADE);

	# set fade delay here, if wanted
	if ($fadeperc) {
		my $origsec = $sec;
		$sec *= (1-$fadeperc);
		push @{$FadeStack[0]}, ($origsec-$sec);
		push @{$FadeStack[1]}, 0; # no volumechange on this one
		Dlog('Due to '.$fadeperc.' FadeDelay we\'re fading in: '.$sec.' seconds (original was '.$origsec.')');
	}
	else {Dlog('Fading in: '.$sec.' seconds');}

	Dlog('** Starting FadeCurve calculations **');
	my ($swing,$previous) = (0,0);
	for (1..$delta)
	{
		# Calculate time 'x' for next volumechange
		my $x = (($_/$delta) ** (1/$fadecurve))*$sec;

		# If position is too soon, we'll skip it and add more volume next time
		if (($x-$previous) < SMALLESTFADE) { $swing += 1; }
		else
		{
			push @{$FadeStack[0]}, ($x-$previous); # we want relative time in stack
			push @{$FadeStack[1]}, 1+$swing;
			Dlog($_.' ('.(1+$swing).') = '.($x-$previous).' ('.$x.')');
			$swing = 0;
			$previous = $x;
		}
	}

	# if there's still some need for change, we'll add it to last item
	${$FadeStack[1]}[scalar@{$FadeStack[1]}-1] += $swing if ($swing);

	Fade($to,1);
	return 1;
}

sub Fade
{
	my ($goal,$init) = @_;

	unless ($init)
	{
		my $CurVol = ::GetVol();
		my $volchange = (scalar@{$FadeStack[1]})? (shift @{$FadeStack[1]}) : 1;
		$volchange = ::min($volchange,abs($goal-$CurVol));

		if ($CurVol < $goal) {::UpdateVol($CurVol+$volchange);}
		elsif ($CurVol > $goal) {::UpdateVol($CurVol-$volchange);}
		else {return 0;}#returning false destroys timeout
	}

	Glib::Source->remove($fadehandle) if (defined $fadehandle);
	$fadehandle = undef;
	unless (scalar@{$FadeStack[0]}) { IsSunshineOn(); return 0; }

	my $next = shift @{$FadeStack[0]};
	$fadehandle = Glib::Timeout->add($next*1000, sub { return Fade($goal); },1);

	return 1;
}

sub KillFade
{
	Dlog('Killing fade');
	Glib::Source->remove($fadehandle) if (defined $fadehandle);
	$fadehandle = undef;
	@FadeStack = ();
	IsSunshineOn();

	return 1;
}

sub CreateNewAlarm
{
	my $set = shift;

	Dlog('Creating new alarm '.$set.'. \''.$Alarm{$set}->{Name}.'\'');
	if ($Alarm{$set}->{LaunchAt}) {
		my $timetolaunch = GetShortestTimeTo($Alarm{$set}->{LaunchHour}.':'.$Alarm{$set}->{LaunchMin});
		$Alarm{$set}->{alarmhandle} = Glib::Timeout->add($timetolaunch*1000,sub
			{
				CreateNewAlarm($set) unless ($Alarm{$set}->{IsON});
				IsSunshineOn();
				return 0;
		},1);
		$Alarm{$set}->{LaunchAt} = 0;
		$Alarm{$set}->{IsOn} = 0; # we don't concider 'waiting for launch' as 'on' for alarm
		Dlog('Waiting for ['.sprintf("%.2d\:%.2d",$Alarm{$set}->{LaunchHour},$Alarm{$set}->{LaunchMin}).'] to launch Wake-alarm (in '.$timetolaunch.' seconds)');
		return 2; # we'll be back after a while
	}

	if ($Alarm{$set}->{UseFade}) {
		if ($Alarm{$set}->{DelayTime})
		{
			unless (CreateFade($Alarm{$set}->{DelayTime},$Alarm{$set}->{FadeTo},$Alarm{$set}->{DelayCurve},$Alarm{$set}->{DelayPerc}))
			{
				Dlog('Error in CreateFade! Abandoning alarm creation.');
				return 0;
			}
		}
		else { Dlog('No time to fade! Setting volume ('.$Alarm{$set}->{FadeTo}.') immediately'); ::UpdateVol($Alarm{$set}->{FadeTo}) if (::GetVol() != $Alarm{$set}->{FadeTo});}
	}

	$Alarm{$set}->{IsOn} = 1;
	$Alarm{$set}->{StartTime} = time;
	$Alarm{$set}->{InitialAlbum} = join " ", Songs::Get($::SongID,qw/album_artist year album/);
	$Alarm{$set}->{PassedTracks} = ($::TogPlay)? -1 : 0; # don't count  current song if it's already playing

	DoCommand($Alarm{$set}->{InitialCommand}) unless ($LaunchCommands{$Alarm{$set}->{InitialCommand}} eq '');

	# We only create sleep-timer (alarmhandle) if needed
	if (defined $Alarm{$set}->{SC})
	{
		my @scs = split /\|/, $Alarm{$set}->{SC};
		shift @scs;
		for (@scs)
		{
			next unless ($SleepConditions{$_}->{Flags} =~ /t/);

			Dlog('Creating alarmhandle for Time ('.($Alarm{$set}->{TimeCount}*60).' sec)');
			$Alarm{$set}->{alarmhandle} = Glib::Timeout->add($Alarm{$set}->{TimeCount}*60*1000, sub {
					CheckDelayConditions();
					return 0;
				},1);
		}
	}

	return 1;
}

sub SetupNewAlarm
{
	my $set = shift;

	Dlog('Setting properties for alarm '.$set);
	for (@AlarmFields) { $Alarm{$set}->{$_} = $::Options{OPT.$_}; }

	if ($Alarm{$set}->{ManualSleepConditions}) {
		$Alarm{$set}->{SC} = ($Alarm{$set}->{'ManualReqCombo'} =~ /any/)? 'any' : 'all';
		for (sort keys %SleepConditions) {
			next unless ($::Options{OPT.'MS'.$_});
		   	$Alarm{$set}->{SC} .= '|'.$_; 
			$Alarm{$set}->{$SleepConditions{$_}->{OPT_setting}} = $::Options{OPT.'MS'.$SleepConditions{$_}->{OPT_setting}} if (defined $SleepConditions{$_}->{OPT_setting});
		}
		if ($Alarm{$set}->{SC} =~ /^(any|all)$/) { $Alarm{$set}->{SC} = 'any|5_Immediate';}
	}
	else { 
		($Alarm{$set}->{SC}) = grep {($::Options{OPT.'DelayMode'} =~ /^$SleepConditions{$_}->{label}/) } (keys %SleepConditions);
		$Alarm{$set}->{SC} = 'any|'.$Alarm{$set}->{SC};
	}
	
	$Alarm{$set}->{DelayTime} = CalculateDelayTime($set);

	return 1;
}

# KillAlarm doesn't stop ongoing fades
sub KillAlarm
{
	my @kill = @_;
	@kill = (1..MAXALARMS) if ((scalar@kill) and ($kill[0] < 0));

	for my $set (@kill)
	{
		Dlog('Killing alarm no: '.$set.'. \''.($Alarm{$set}->{Name} || 'Noname').'\'');
		next unless ((defined $Alarm{$set}) and ($Alarm{$set}->{IsOn}));
		Glib::Source->remove($Alarm{$set}->{alarmhandle}) if (defined $Alarm{$set}->{alarmhandle});
		delete $Alarm{$set};
	}

	IsSunshineOn();
	return 1;
}

sub KillEverything
{
	KillAlarm(-1);
	KillFade();
	# IsSunshineOn is called in functions abowe

	return 1;
}

sub IsSunshineOn
{
	my $ON = 0;
	my @reason;

	if ((defined $fadehandle) and (scalar@FadeStack)) {
		$ON = 1;
		push @reason, 'Sunshine is fading';
	}

	unless ($ON) {
		for (1..MAXALARMS) { if ($Alarm{$_}->{IsOn}) { $ON = 1; last;} }
		push @reason, 'There is an active alarm' if ($ON);
	}

	if ($::Options{OPT.'Sunshine3IsOn'} != $ON)
	{ 
		$::Options{OPT.'Sunshine3IsOn'} = $ON;
		Dlog('SunshineStatus has changed to :'.(($ON)? 'ON' : 'OFF').((scalar@reason)? ' ('.(join " / ", @reason).')' : ''));
		::HasChanged('Sunshine3Status');
	}

	return $ON;
}

sub LayoutButtonMenu
{	
	my $advanced = shift;

	my $menu = Gtk2::Menu->new;

	#helper method
	my $append=sub
	 {	my ($menu,$set)=@_;
		my $item = Gtk2::CheckMenuItem->new_with_label($::Options{OPT.'preset'.$set.'Name'} || 'Preset '.$set);
		my $true = ($Alarm{$set}->{IsOn})? 1 : 0;
		$item->set_active($true);
		$item->signal_connect (activate => sub { Launch($set);});
		$menu->append($item);
	 };

	#Launch / menu
	my $sleepmenu= Gtk2::Menu->new;
	my $launchmenu = Gtk2::MenuItem->new("Launch");

	my $max = ($advanced)? MAXALARMS : 3;
	$append->($sleepmenu,$_) for (1..$max);

	$launchmenu->set_submenu($sleepmenu);
	$menu->append($launchmenu);

	# Kill single alarm (if we have one)
	my @alarms = grep { $Alarm{$_}->{IsOn}} (1..MAXALARMS);

	if ((scalar@alarms) and ($advanced))
	{
		my $activemenu= Gtk2::Menu->new;
 		my $aitem = Gtk2::MenuItem->new('Kill Alarm');

		my $append2=sub 
		{
			my ($menu,$set)=@_;
			my $item = Gtk2::MenuItem->new_with_label(($::Options{OPT.'preset'.$set.'Name'} || 'Preset '.$set));
			$item->signal_connect (activate => sub { KillAlarm($set);});
			$menu->append($item);
		 };

		$append2->($activemenu,$_) for (@alarms);
		$aitem->set_submenu($activemenu);
		$menu->append($aitem);
	}

	# Stop volumefade (if it's on)
	if ((defined $fadehandle) and (scalar@FadeStack))
	{
		$menu->append(Gtk2::SeparatorMenuItem->new);
		my $killfade = Gtk2::MenuItem->new('Stop Volumefade');
		$killfade->signal_connect(activate => \&KillFade);
		$menu->append($killfade);
	}

	#Stop Everything
	$menu->append(Gtk2::SeparatorMenuItem->new);
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
