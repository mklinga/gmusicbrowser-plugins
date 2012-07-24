# Gmusicbrowser: Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
# Sunshine3: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# TODO
# - fadecurve/delay implementation
# - multiple sleepconditions?
# - preset changing in launchDialog
# - prefbox
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
	MAXALARMS => 3,
};

use utf8;

::SetDefaultOptions(OPT, LaunchAt => 0, LaunchHour => 19, LaunchMin => 0, InitialCommand => 'Nothing', FinishingCommand => 'Nothing',
	FadeTo => 0, DelayMode => _('After minutes'), FadeCombo => _('Linear'), WakeFadeCombo => _('Linear'), FadeDelayCombo => _('No Delay'),
	FadeCurve => 1, FadeDelayPerc => 0, UseDLog => 1, Button1Item => 'Sleep', Button2Item => 'Simplefade', Button3Item => 'Wake',
	TimeCount => 30, TrackCount => 8);

my %dayvalues= ( Mon => 1, Tue => 2,Wed => 3,Thu => 4,Fri => 5,Sat => 6,Sun => 0);
my %sunshine_button=
(	class	=> 'Layout::Button',
	stock	=> 'plugin-sunshine3',
	tip	=> " Sunshine v".$VNUM,
	click1 => sub {Launch(1);},
	click2 => sub {Launch(2);},
	click3 => sub {Launch(3);},
	autoadd_type	=> 'button main',
);

# dialog layout relies on sorting items (hardcode is bad, mkay?)
my %SleepConditions = (
	'1_Queue' => {
		'label' => _('Queue empty'),
		'AddLabel' => '',
		CalcLength => 'my $l=0; $l += Songs::Get($_,qw/length/) for (@$::Queue); return $l;',
		IsFinished => 'return (!scalar@$::Queue)',
		FinishOnNext => 1,
		AddCurrent => 1},
	'2_Albumchange' => {
		'label' => _('On albumchange'),
		'AddLabel' => '',
		CalcLength => 'my $l=0; my $IDs = AA::GetIDs(qw/album/,Songs::Get_gid($::SongID,qw/album/));Songs::SortList($IDs,$::Options{Sort});splice (@$IDs, 0, Songs::Get($::SongID,qw/track/));$l += Songs::Get($_,qw/length/) for (@$IDs); return $l;',
		IsFinished => 'return ($Alarm{$set}->{InitialAlbum} ne (join " ",Songs::Get($::SongID,qw/album_artist album/)))',
		FinishOnNext => 0,
		AddCurrent => 1},
	'3_Count' => {
		'label' => _('After') ,
		'AddLabel' => _(' tracks'), OPT_setting => 'TrackCount',
		CalcLength => 'my @IDs = ::GetNextSongs($Alarm{$set}->{TrackCount}); splice (@IDs, 0,1);my $l=0;$l += Songs::Get($_,qw/length/) for (@IDs);return $l;',
		IsFinished => 'return (($Alarm{$set}->{PassedTracks}++) => $Alarm{$set}->{TrackCount})',
		FinishOnNext => 1,
		AddCurrent => 1},
	'4_Time' => {
		'label' => _('After') ,
		'AddLabel' => _(' minutes'), OPT_setting => 'TimeCount',
		CalcLength => 'return 60*$Alarm{$set}->{TimeCount}',
		IsFinished => 'return (time-$Alarm{$set}->{StartTime} >= ($Alarm{$set}->{TimeCount}*60))',
		FinishOnNext => 0,
		AddCurrent => 0},
);

my %LaunchCommands = (
	'Play' => '::Play()',
	'Pause' => '::Pause()',
	'Nothing' => '',
);

my @AlarmFields = ('FadeTo', 'LaunchAt','LaunchHour','LaunchMin','InitialCommand','UseFade','DelayMode','FinishingCommand', 'TimeCount','TrackCount');

my %Alarm;
my $handle;
my $fadehandle;
my $oldID=-1;
my @FadeStack;
my $dlogfirst=1;

sub Start
{
	Layout::RegisterWidget('Sunshine3Button'=>\%sunshine_button);
	::Watch($handle, PlayingSong => \&SongChanged);

	$::Options{OPT.'scCombo'} = $SleepConditions{'1_Queue'}->{label} unless (defined $::Options{OPT.'scCombo'});

}
sub Stop
{
	Layout::RegisterWidget('Sunshine3Button');
	::UnWatch($handle,'PlayingSong') if ($handle);
	KillAlarm(-1);
	Glib::Source->remove($fadehandle) if (defined $fadehandle);
	$fadehandle = undef;

}

sub prefbox
{
	my $vbox=::Vpack();
	return $vbox;
}

sub SongChanged
{
	return if ($::SongID == $oldID);

	CheckDelayConditions();

	return 1;
}

sub CheckDelayConditions
{
	my $s = shift;
	my @a = ($s)? ($s) : (1..9);

	Dlog('Checking if it\'s time to sleep already');
	for my $set (@a)
	{
		my ($sleepnow, $finishonnext) = (0,0);
		next unless ($Alarm{$set}->{IsOn});

		if ($Alarm{$set}->{WaitingForNext}) { FinishAlarm(); return 1; }

		if (eval($SleepConditions{$Alarm{$set}->{SC}}->{IsFinished}))
		{
			Dlog('Alarm '.$set.' has finished!');
			if ($Alarm{$set}->{FinishOnNext}) { $Alarm{$set}->{WaitingForNext} = 1;}
			else { FinishAlarm($set);}
		}
	}
	
	return 1;

}

sub FinishAlarm
{
	my $set = shift;

	return 0 unless ($Alarm{$set}->{IsOn});

	Dlog('Going to sleep now');
	DoCommand($Alarm{$set}->{FinishingCommand});
	KillAlarm($set);

	return 1;
}

sub Launch
{
	my $set = (shift || 1);

	if (LaunchDialog($set) eq 'ok')
	{
		Dlog('Preparing to launch alarm '.$set.'.');
		KillAlarm($set) if ((defined $Alarm{$set}) and ($Alarm{$set}->{IsOn}));
		#copy values from dialog to $Alarm{$set}
		unless (SetupNewAlarm($set)) { Dlog('SetupNewAlarm FAILED!'); return 0;}
		# launch the actual alarm
		unless (CreateNewAlarm($set)) { Dlog('CreateNewAlarm FAILED!'); return 0;}
	}

	return 1;
}

sub SavePreset
{
	my $set = shift;

	for (@AlarmFields) {
		$::Options{OPT.'preset'.$set.$_} = $::Options{OPT.$_} if (defined $::Options{OPT.$_} );
	}

	return 1;
}

sub LoadPreset
{
	my $set = shift;

	return unless (defined $::Options{OPT.'preset'.$set});

	for (@AlarmFields) {
		$::Options{OPT.$_} = $::Options{OPT.'preset'.$set.$_} if (defined $::Options{OPT.'preset'.$set.$_});
	}

	return 1;
}

sub LaunchDialog
{
	my ($set) = @_;

	LoadPreset($set);

	my $scheme = "[LA][IC][VF][DM][FC]";
	my @commands = (sort keys %LaunchCommands);
	my @p; 
	push @p, $SleepConditions{$_}->{label}. $SleepConditions{$_}->{AddLabel} for (sort keys %SleepConditions);

	my $LaunchDialog = Gtk2::Dialog->new(_('Launch Sunshine'), undef, 'modal');
	my $cancelbutton = $LaunchDialog->add_button('gtk-cancel', 'cancel');
	$LaunchDialog->add_button('gtk-ok', 'ok');
	$LaunchDialog->set_position('center-always');

	my $vbox;

	# Launch at
	my $check1 = ::NewPrefCheckButton(OPT.'LaunchAt','Launch at: ');
	my $spin1 = ::NewPrefSpinButton(OPT.'LaunchHour',0,24,wrap=>1);
	my $l1 = Gtk2::Label->new(_(':'));
	my $spin2 = ::NewPrefSpinButton(OPT.'LaunchMin',0,59,wrap=>1);
	my $LAUNCH_AT = ($scheme =~ /\[LA\]/)? [$check1,$spin1,$l1,$spin2] : undef;
	
	# Initial command
	my $l2 = Gtk2::Label->new('Initial command: ');
	my $combo1 = ::NewPrefCombo(OPT.'InitialCommand',\@commands);
	my $INITIAL_COMMAND = ($scheme =~ /\[IC\]/)? [$l2,$combo1] : undef;

	# Volume fade
	my $check2 = ::NewPrefCheckButton(OPT.'UseFade','Fade volume to');
	my $spin3 = ::NewPrefSpinButton(OPT.'FadeTo',0,100);
	my $but1 = ::NewIconButton('gtk-refresh',undef,sub { $::Options{OPT.'FadeTo'} = ::GetVol; $spin3->set_value($::Options{OPT.'FadeTo'});}	,undef);
	my $VOLUME_FADE = ($scheme =~ /\[VF\]/)? [$check2,$spin3,$but1] : undef;

	# Delaymode
	my $l3 = Gtk2::Label->new('Delaymode');
	my $spin4 = ::NewPrefSpinButton(OPT.'DelayModeEntry',1,720, cb => sub {
			my ($scitem) = grep {($::Options{OPT.'DelayMode'} =~ /^$SleepConditions{$_}->{label}$SleepConditions{$_}->{AddLabel}/) } (keys %SleepConditions);
			$::Options{OPT.$SleepConditions{$scitem}->{OPT_setting}} = $::Options{OPT.'DelayModeEntry'} if (exists $SleepConditions{$scitem}->{OPT_setting});
	});
	my $refr = sub {
		my ($scitem) = grep {($::Options{OPT.'DelayMode'} =~ /^$SleepConditions{$_}->{label}$SleepConditions{$_}->{AddLabel}/) } (keys %SleepConditions);
		$spin4->set_value($::Options{OPT.$SleepConditions{$scitem}->{OPT_setting}}) if (exists $SleepConditions{$scitem}->{OPT_setting});
		$spin4->set_sensitive(($SleepConditions{$scitem}->{AddLabel} ne '')? 1 : 0);
	};
	my $combo2 = ::NewPrefCombo(OPT.'DelayMode',\@p, cb => $refr);
	my $DELAY_MODE = ($scheme =~ /\[DM\]/)? [$l3,$combo2,$spin4] : undef;
	
	# Finishing command
	my $l4 = Gtk2::Label->new('Finishing command: ');
	my $combo3 = ::NewPrefCombo(OPT.'FinishingCommand',\@commands);
	my $FINISHING_COMMAND = ($scheme =~ /\[FC\]/)? [$l4,$combo3] : undef;

	$vbox = ::Vpack($LAUNCH_AT,$INITIAL_COMMAND,$VOLUME_FADE,$DELAY_MODE,$FINISHING_COMMAND);
	&$refr;

	$LaunchDialog->get_content_area()->add($vbox);
	$LaunchDialog->set_default_response ('cancel');
	$LaunchDialog->show_all;
	$LaunchDialog->set_focus($cancelbutton);

	my $response = $LaunchDialog->run;
	
	$LaunchDialog->destroy();
	SavePreset($set) if ($response eq 'ok');

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

	my $length = eval($SleepConditions{$Alarm{$set}->{SC}}->{CalcLength});
	if ($@) { Dlog('Errors in eval @ CalculateDelayTime!');}
	$length += (Songs::Get($::SongID,'length')-($::PlayTime || 0)) if ($SleepConditions{$Alarm{$set}->{SC}}->{AddCurrent});
Dlog ($length);
	return $length;
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
	return 0 unless (scalar@{$FadeStack[0]});

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

	return 1;
}

sub CreateNewAlarm
{
	my $set = shift;

	Dlog('Creating new alarm \''.$set.'\'');
	if ($Alarm{$set}->{LaunchAt}) {
		my $timetolaunch = GetShortestTimeTo($Alarm{$set}->{LaunchHour}.':'.$Alarm{$set}->{LaunchMin});
		$Alarm{$set}->{alarmhandle} = Glib::Timeout->add($timetolaunch*1000,sub
			{
				CreateNewAlarm($set);
				return 0;
		},1);
		$Alarm{$set}->{LaunchAt} = 0;
		$Alarm{$set}->{IsOn} = 1;
		Dlog('Waiting for ['.sprintf("%.2d\:%.2d",$Alarm{$set}->{LaunchHour},$Alarm{$set}->{LaunchMin}).'] to launch Wake-alarm (in '.$timetolaunch.' seconds)');
		return 2; # we'll be back after a while
	}

	if ($Alarm{$set}->{UseFade}) {
		if ($Alarm{$set}->{DelayTime})
		{
			my $curve = $::Options{OPT.'FadeCurve'} || 1;
			my $perc = $::Options{OPT.'FadeDelayPerc'} || 0;
			unless (CreateFade($Alarm{$set}->{DelayTime},$Alarm{$set}->{FadeTo},$curve,$perc))
			{
				Dlog('Error in CreateFade! Abandoning alarm creation.');
				return 0;
			}
		}
		else { Dlog('No time to fade! Setting volume ('.$Alarm{$set}->{FadeTo}.') immediately'); ::UpdateVol($Alarm{$set}->{FadeTo}) if (::GetVol() != $Alarm{$set}->{FadeTo});}
	}

	$Alarm{$set}->{IsOn} = 1;

	$Alarm{$set}->{StartTime} = time;
	$Alarm{$set}->{InitialAlbum} = join " ", Songs::Get($::SongID,qw/album_artist album/);
	$Alarm{$set}->{PassedTracks} = ($::TogPlay)? -1 : 0; # don't count  current song if it's already playing

	DoCommand($Alarm{$set}->{InitialCommand}) unless ($Alarm{$set}->{InitialCommand} eq 'Nothing');

	# We only create sleep-timer (alarmhandle) if we wait for specific time, other cases are called from SongChanged
	if ($Alarm{$set}->{SC} =~ /Time/)	{
		Dlog('Creating alarmhandle for 4_Time ('.($Alarm{$set}->{TimeCount}*60).' sec)');
		$Alarm{$set}->{alarmhandle} = Glib::Timeout->add($Alarm{$set}->{TimeCount}*60*1000, sub {
				CheckDelayConditions();
				return 0;
			},1);
	}
	return 1;
}

sub SetupNewAlarm
{
	my $set = shift;

	Dlog('Setting alarm '.$set.' up');

	for (@AlarmFields) {
		$Alarm{$set}->{$_} = $::Options{OPT.$_};
	}

	($Alarm{$set}->{SC}) = grep {($::Options{OPT.'DelayMode'} =~ /^$SleepConditions{$_}->{label}$SleepConditions{$_}->{AddLabel}/) } (keys %SleepConditions);
	$Alarm{$set}->{DelayTime} = CalculateDelayTime($set);

	return 1;
}

# KillAlarm doesn't stop ongoing fades
sub KillAlarm
{
	my @kill = @_;
	@kill = (0..9) if ((scalar@kill) and ($kill[0] < 0));

	for my $set (@kill)
	{
		Dlog('Killing alarm no: '.$set);
		next unless ((defined $Alarm{$set}) and ($Alarm{$set}->{IsOn}));
		Glib::Source->remove($Alarm{$set}->{alarmhandle}) if (defined $Alarm{$set}->{alarmhandle});
		delete $Alarm{$set};
	}

	return 1;
}

sub Dlog
{
	my $t = shift;

	return 0 unless ($::Options{OPT.'UseDLog'});

	my $DlogFile = $::HomeDir.'sunshine3.log';
	my $method = ($dlogfirst)? '>' : '>>';
	$dlogfirst = 0;

	my $content = '['.localtime(time).'] '.$t."\n";

	open my $fh,$method,$DlogFile or warn "Error opening '$DlogFile' for writing : $!\n";
	print $fh $content   or warn "Error writing to '$DlogFile' : $!\n";
	close $fh;

	return 1;


}

1
