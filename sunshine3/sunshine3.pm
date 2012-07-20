# Gmusicbrowser: Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
# Sunshine3: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# TODO
# - option to launch 'simple fade' without sleep/wake (middle button)
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
};

use utf8;

::SetDefaultOptions(OPT, Sleep_UseFade => 1, Simplefade_FadeTo => 50, Sleep_FadeTo => 0, Sleep_TrackCount => 5, Sleep_TimeCount => 30,
		Wake_UseFade => 1, Wake_FadeTo => 100, Simplefade_FadeMin => 30, Wake_FadeMin => 30, Wake_LaunchHour => 6, Wake_LaunchMin => 30,
	ShowMultipleSleepConditions => 0, FadeCombo => _('Linear'), WakeFadeCombo => _('Linear'), FadeDelayCombo => _('No Delay'),
	SleepFadeCurve => 1, WakeFadeCurve => 1, FadeDelayPerc => 0, UseDLog => 1, Simplefade_FadeCurve => 1,
	Button1Item => 'Sleep', Button2Item => 'Simplefade', Button3Item => 'Wake');

my %dayvalues= ( Mon => 1, Tue => 2,Wed => 3,Thu => 4,Fri => 5,Sat => 6,Sun => 0);
my %sunshine_button=
(	class	=> 'Layout::Button',
	stock	=> 'plugin-sunshine3',
	tip	=> " Sunshine v".$VNUM,
	click1 => sub {Launch($::Options{OPT.'Button1Item'});},
	click2 => sub {Launch($::Options{OPT.'Button2Item'});},
	click3 => sub {Launch($::Options{OPT.'Button3Item'});},
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
		IsFinished => 'return ($Alarm{InitialAlbum} ne (join " ",Songs::Get($::SongID,qw/album_artist album/)))',
	       	FinishOnNext => 0,
		AddCurrent => 1},
	'3_Count' => { 
		'label' => _('After') ,
	       	'AddLabel' => _(' tracks '), OPT_setting => '_TrackCount',
		CalcLength => 'my @IDs = ::GetNextSongs($Alarm{Sleep}->{TrackCount}); splice (@IDs, 0,1);my $l=0;$l += Songs::Get($_,qw/length/) for (@IDs);return $l;',
		IsFinished => 'return (($Alarm{Sleep}->{PassedTracks}++) => $Alarm{Sleep}->{TrackCount})',
	       	FinishOnNext => 1,
		AddCurrent => 1},
	'4_Time' => { 
		'label' => _('After') ,
	       	'AddLabel' => _(' minutes '), OPT_setting => '_TimeCount',
		CalcLength => 'return 60*$Alarm{Sleep}->{TimeCount}',
		IsFinished => 'return (time-$Alarm{Sleep}->{StartTime} >= ($Alarm{Sleep}->{TimeCount}*60))',
	       	FinishOnNext => 0,
		AddCurrent => 0},
);

my %Alarm;
my $handle; my $fadehandle;
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
	KillAlarm('Sleep','Wake');
	Glib::Source->remove($fadehandle) if (defined $fadehandle);
	$fadehandle = undef;

}

sub prefbox
{
	my $scCheck = ::NewPrefCheckButton(OPT.'ShowMultipleSleepConditions',_('Show multiple sleepconditions'));
	my $l1 = Gtk2::Label->new(_('Fademode for sleep: '));
	my $l2 = Gtk2::Label->new(_('Delay before fading: '));
	my $l3 = Gtk2::Label->new(_('Fademode for waking up: '));

	my %FadeModes = (_('Linear') => 1,_('Smooth') => 1.4,_('Smoothest') => 1.8);
	my %FadeDelays = (_('No Delay') => 0,_('Small Delay') => 0.25,_('Long Delay') => 0.5);
	my %WakeFadeModes = (_('Linear') => 1,_('Smooth') => 1.4,_('Steep') => 0.6);

	my @p = (sort keys %FadeModes);
	my $FadeModeCombo = ::NewPrefCombo(OPT.'FadeCombo',\@p, cb => sub {$::Options{OPT.'SleepFadeCurve'} = $FadeModes{$::Options{OPT.'FadeCombo'}}; });

	@p = (sort keys %WakeFadeModes);
	my $WakeFadeModeCombo = ::NewPrefCombo(OPT.'WakeFadeCombo',\@p, cb => sub {$::Options{OPT.'WakeFadeCurve'} = $WakeFadeModes{$::Options{OPT.'WakeFadeCombo'}}; });

	@p = (_('No Delay'), _('Small Delay'), _('Long Delay'));
	my $FadeDelayCombo = ::NewPrefCombo(OPT.'FadeDelayCombo',\@p, cb => sub { $::Options{OPT.'FadeDelayPerc'} = $FadeDelays{$::Options{OPT.'FadeDelayCombo'}}; });

	my $frame = Gtk2::Frame->new(" Icon actions ");
	@p = ('Sleep','Wake','Simplefade');
	my $lb1 = Gtk2::Label->new('Left-click: ');
	my $but1combo = ::NewPrefCombo(OPT.'Button1Item',\@p );
	my $lb2 = Gtk2::Label->new('Middle-click: ');
	my $but2combo = ::NewPrefCombo(OPT.'Button2Item',\@p );
	my $lb3 = Gtk2::Label->new('Right-click: ');
	my $but3combo = ::NewPrefCombo(OPT.'Button3Item',\@p );
	$frame->add(::Vpack([$lb1,$but1combo],[$lb2,$but2combo],[$lb3,$but3combo]));

	my $vbox=::Vpack($scCheck,[$l1,$FadeModeCombo,$l2,$FadeDelayCombo],[$l3,$WakeFadeModeCombo],$frame);
	return $vbox;
}

sub SongChanged
{
	return if ($::SongID == $oldID);

	CheckSleepConditions();

	return 1;
}

sub CheckSleepConditions
{
	my ($sleepnow, $sccount, $finishonnext) = (0,0,0);

	if ($Alarm{Sleep}->{IsOn})
	{
		Dlog('Checking if it\'s time to sleep already ...');
		if ($Alarm{Sleep}->{WaitingForNext}) { GoSleep(); return 1; }

		for (sort keys %SleepConditions)
		{
			next unless ($Alarm{Sleep}->{'SC_'.$_});

			$sccount++;
			if (eval($SleepConditions{$_}->{IsFinished}))
			{
				$sleepnow++;
				$finishonnext ++ if ($Alarm{Sleep}->{FinishOnNext});
			} 
		}
	}
	return 0 unless ($sccount);

	if (($Alarm{Sleep}->{RequireConditions} =~ /any$/) and ($sleepnow > 0))
	{
		if ($sleepnow > $finishonnext) { GoSleep(); }
		else { Dlog('Will go to sleep after current song is finished'); $Alarm{Sleep}->{WaitingForNext} = 1; }
	}
	elsif (($Alarm{Sleep}->{RequireConditions} =~ /all$/) and ($sleepnow == $sccount))
	{
		if ($finishonnext == 0) { GoSleep(); }
		else { Dlog('Will go to sleep after current song is finished'); $Alarm{Sleep}->{WaitingForNext} = 1; }
	}

	return 1;

}

sub GoSleep
{
	return 0 unless ($Alarm{Sleep}->{IsOn});

	Dlog('Going to sleep now');
	::Pause;
	KillAlarm('Sleep');

	return 1;
}

sub WakeUp
{
	return 0 unless ($Alarm{Wake}->{IsOn});

	Dlog('Waking up!');
	::Play unless ($::TogPlay);
	KillAlarm('Wake');

	return 1;
}

sub Launch
{
	my $set = shift;
	$set = 'Sleep' unless ($set =~ /^Wake$|^Simplefade$/);

	if (LaunchDialog($set) eq 'ok')
	{
		if ($set eq 'Simplefade')
		{
			unless (CreateFade($::Options{OPT.$set.'_FadeMin'}*60,$::Options{OPT.$set.'_FadeTo'},$::Options{OPT.'Simplefade_FadeCurve'},0))
			{
				Dlog('Failed');
				return 0;
			}
		}
		else
		{
			Dlog('Preparing to launch '.$set);
			KillAlarm($set) if ((defined $Alarm{$set}) and ($Alarm{$set}->{IsOn}));
			#copy values from dialog to $Alarm{$set}
			unless (SetupNewAlarm($set)) { Dlog('SetupNewAlarm FAILED!'); return 0;}
			# launch the actual alarm
			unless (CreateNewAlarm($set)) { Dlog('CreateNewAlarm FAILED!'); return 0;}
		}
	}

	return 1;
}

sub LaunchDialog
{
	my $set = shift;

	my $LaunchDialog = Gtk2::Dialog->new(_('Launch Sunshine'), undef, 'modal');
	$LaunchDialog->add_buttons('gtk-cancel' => 'cancel','gtk-ok' => 'ok');
	$LaunchDialog->set_position('center-always');

	my $vbox;
	my $check1 = ::NewPrefCheckButton(OPT.$set.'_UseFade','Fade volume to');
	my $l1 = Gtk2::Label->new(_('..: New '.$set.'alarm :..'));
	my $warnlabel; my $killbutton;
	if ($Alarm{$set}->{IsOn}) {
		$warnlabel = Gtk2::Label->new(_('There is already an active Alarm!'));
		$killbutton = Gtk2::Button->new('Kill');
		$killbutton->signal_connect(clicked => sub {KillAlarm($set); KillFade(); $warnlabel->hide; $killbutton->hide;});
	}
	my $spin1 = ::NewPrefSpinButton(OPT.$set.'_FadeTo',0,100);
	my $but1 = ::NewIconButton('gtk-refresh',undef,sub {
		$::Options{OPT.$set.'_FadeTo'} = ::GetVol;
		$spin1->set_value($::Options{OPT.$set.'_FadeTo'});}
	,undef);

	# we have certain mode-specific elements
	if ($set eq 'Sleep')
	{
		my @conditionchecks;
		my %scs;
		if ($::Options{OPT.'ShowMultipleSleepConditions'})
		{
			for (sort keys %SleepConditions) {
				push @conditionchecks, ::NewPrefCheckButton(OPT.$set.'_SC_'.$_,$SleepConditions{$_}->{label});
			}
			my $l3 = Gtk2::Label->new($SleepConditions{'3_Count'}->{AddLabel});
			my $l4 = Gtk2::Label->new($SleepConditions{'4_Time'}->{AddLabel});
			my $entry1 = ::NewPrefSpinButton(OPT.$set.'_TrackCount',1,100);
			my $entry2 = ::NewPrefSpinButton(OPT.$set.'_TimeCount',1,720);
			my @tv = ('Require all','require_all','Require any','require_any');
			my @radios = ::NewPrefRadio(OPT.$set.'_RequireConditions',\@tv);

			my $frame=Gtk2::Frame->new(" Sleep conditions ");
			$frame->add(::Vpack($conditionchecks[0],$conditionchecks[1],['_',$conditionchecks[2],$entry1,$l3],['_',$conditionchecks[3],$entry2,$l4],[@radios]));

			$vbox = ::Vpack($l1,[$warnlabel,$killbutton],['_',$check1,$but1,$spin1],$frame);
		}
		else
		{
			my $scEntry = ::NewPrefSpinButton(OPT.'scSpinSimple',1,720,cb => sub {
					my ($scitem) = grep {($::Options{OPT.'scCombo'} =~ /^$SleepConditions{$_}->{label}$SleepConditions{$_}->{AddLabel}/) } (keys %SleepConditions);
					$::Options{OPT.$set.$SleepConditions{$scitem}->{OPT_setting}} = $::Options{OPT.'scSpinSimple'};
			});

			my @scItems;
			push @scItems, $SleepConditions{$_}->{label}.$SleepConditions{$_}->{AddLabel} for (keys %SleepConditions);
			my $refr = sub
			{
				for (sort keys %SleepConditions) {
					if ($::Options{OPT.'scCombo'} =~ /^$SleepConditions{$_}->{label}$SleepConditions{$_}->{AddLabel}/) {
				       		$::Options{OPT.$set.'_SC_'.$_} = 1;
						if ($SleepConditions{$_}->{AddLabel} ne '')
						{
							$scEntry->set_value($::Options{OPT.$set.$SleepConditions{$_}->{OPT_setting}});
							$scEntry->set_sensitive(1);
						}
						else { $scEntry->set_sensitive(0); }
					}
					else { $::Options{OPT.$set.'_SC_'.$_} = 0; }
				}
			};

			my $scCombo = ::NewPrefCombo(OPT.'scCombo',\@scItems,cb => $refr);
			my $l3 = Gtk2::Label->new(_('Sleepcondition: '));

			$vbox = ::Vpack($l1,[$warnlabel,$killbutton],['_',$check1,$but1,$spin1],[$l3,$scCombo,$scEntry]);
			&$refr;
		}

	}
	elsif ($set eq 'Wake')
	{
		my $check2 = ::NewPrefCheckButton(OPT.$set.'_LaunchDelayed','Launch at: ');
		my $l3 = Gtk2::Label->new(_('in '));
		my $l4 = Gtk2::Label->new(_('min'));
		my $l6 = Gtk2::Label->new(_(':'));
		my $spin3 = ::NewPrefSpinButton(OPT.$set.'_FadeMin',1,1440,wrap=>0);
		my $spin4 = ::NewPrefSpinButton(OPT.$set.'_LaunchHour',0,24,wrap=>1);
		my $spin5 = ::NewPrefSpinButton(OPT.$set.'_LaunchMin',0,59,wrap=>1);

		$vbox = ::Vpack($l1,[$warnlabel,$killbutton],['_',$check1,$but1,$spin1,$l3,'_',$spin3,$l4],
				[$check2,$spin4,$l6,$spin5]);
	}
	else
	{
		my $l2 = Gtk2::Label->new('..: '._('New Fade').' :..');
		my $l3 = Gtk2::Label->new(_(' Fade to: '));
		my $l4 = Gtk2::Label->new(_('in '));
		my $l5 = Gtk2::Label->new(_('min'));
		my $l6 = Gtk2::Label->new(_(' Fadecurve'));
		if ($fadehandle) {
			$warnlabel = Gtk2::Label->new(_('There is already an ongoing fade!'));
			$killbutton = Gtk2::Button->new('Kill');
			$killbutton->signal_connect(clicked => sub {KillFade(); $warnlabel->hide; $killbutton->hide;});

		}
		my $spin2 = ::NewPrefSpinButton(OPT.$set.'_FadeMin',1,1440,wrap=>0);
		my $spin3 = ::NewPrefSpinButton(OPT.$set.'_FadeCurve',0.1,10.0,digits => 1, tip=>'See README for detailed explanation on this');
		$vbox = ::Vpack($l2,[$warnlabel,$killbutton],['_',$l3,$but1,$spin1,$l4,'_',$spin2,$l5],[$l6,$spin3]);

	}

	$LaunchDialog->get_content_area()->add($vbox);
	$LaunchDialog->set_default_response ('cancel');
	$LaunchDialog->show_all;

	my $response = $LaunchDialog->run;
	$LaunchDialog->destroy();

	return $response;
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

sub CalculateSleepTime
{

	my $final;

	for (sort keys %SleepConditions)
	{
		next unless ($Alarm{Sleep}->{'SC_'.$_});
		my $length = eval($SleepConditions{$_}->{CalcLength});
		$length += (Songs::Get($::SongID,'length')-($::PlayTime || 0)) if ($SleepConditions{$_}->{AddCurrent});

		$final = $length if (not defined $final);
		$final = $length if (($Alarm{Sleep}->{RequireConditions} =~ /any$/) and ($length < $final));
		$final = $length if (($Alarm{Sleep}->{RequireConditions} =~ /all$/) and ($length > $final));
	}

	Dlog('Sleepytime seems to be '.$final.' seconds');
	return $final;

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
	Dlog('Creating new Fade! Delta: '.$delta.', Curve: '.$fadecurve.', Delay: '.($fadeperc*100));
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
	return 0 unless (scalar@{$FadeStack[0]});

	my $next = shift @{$FadeStack[0]};
	$fadehandle = Glib::Timeout->add($next*1000, sub { return Fade($goal); },1);

	return 1;
}

sub KillFade
{
	Glib::Source->remove($fadehandle) if (defined $fadehandle);
	$fadehandle = undef;
	@FadeStack = ();

	return 1;
}

sub CreateNewAlarm
{
	my $set = shift;

	if ($Alarm{$set}->{LaunchDelayed}) {
		my $timetolaunch = GetShortestTimeTo($Alarm{$set}->{LaunchHour}.':'.$Alarm{$set}->{LaunchMin});
		$Alarm{$set}->{alarmhandle} = Glib::Timeout->add($timetolaunch*1000,sub
			{
				CreateNewAlarm($set);
				return 0;
		},1);
		$Alarm{$set}->{LaunchDelayed} = 0;
		$Alarm{$set}->{IsOn} = 1;
		Dlog('Waiting for ['.$Alarm{$set}->{LaunchHour}.':'.$Alarm{$set}->{LaunchMin}.'] to launch Wake-alarm (in '.$timetolaunch.' seconds)');
		return 2; # we'll be back after a while
	}

	if ($Alarm{$set}->{UseFade}) {
		if ($Alarm{$set}->{FadeMin})
		{
			my $curve = $::Options{OPT.$set.'FadeCurve'} || 1;
			my $perc = ($set eq 'Sleep')? $::Options{OPT.'FadeDelayPerc'} : 0;
			unless (CreateFade($Alarm{$set}->{FadeMin},$Alarm{$set}->{FadeTo},$curve,$perc))
			{
				Dlog('Error in CreateFade! Abandoning alarm creation.');
				return 0 
			}
		}
		else { Dlog('No time to fade! Setting volume ('.$Alarm{$set}->{FadeTo}.') immediately'); ::UpdateVol($Alarm{$set}->{FadeTo}) if (::GetVol() != $Alarm{$set}->{FadeTo});}
	}

	if ($set eq 'Sleep')
	{
		$Alarm{$set}->{StartTime} = time;
		$Alarm{$set}->{InitialAlbum} = join " ", Songs::Get($::SongID,qw/album_artist album/);
		$Alarm{$set}->{PassedTracks} = ($::TogPlay)? -1 : 0; # don't count  current song if it's already playing
	}
	else { WakeUp(); }

	$Alarm{$set}->{IsOn} = 1;

	# We only create sleep-timer (alarmhandle) if we wait for specific time, other cases are called from SongChanged
	if (($set eq 'Sleep') and ($Alarm{$set}->{SC_4_Time}))	{
		Dlog('Creating alarmhandle for SC_4_Time ('.($Alarm{$set}->{TimeCount}*60).' sec)');
		$Alarm{$set}->{alarmhandle} = Glib::Timeout->add($Alarm{$set}->{TimeCount}*60*1000, sub {
				CheckSleepConditions();
				return 0;
			},1);
	}
	return 1;
}

sub SetupNewAlarm
{
	my $set = shift;

	Dlog('Setting new alarm up');
	my @fields = ('UseFade','FadeTo');
	if ($set eq 'Sleep') {
		push @fields, 'TrackCount','TimeCount','RequireConditions';
		for (sort keys %SleepConditions) { push @fields, 'SC_'.$_;}
       	}
	else { push @fields, 'LaunchDelayed','FadeMin','LaunchHour','LaunchMin'; }

	$Alarm{$set}->{$_} = $::Options{OPT.$set.'_'.$_} for (@fields);
	$Alarm{$set}->{FadeMin} = CalculateSleepTime($set) if ($set eq 'Sleep');
	$Alarm{$set}->{FadeMin} *= 60 if ($set eq 'Wake');

	return 1;
}

# KillAlarm doesn't stop ongoing fades
sub KillAlarm
{
	my @kill = @_;

	for my $set (@kill)
	{
		Dlog('Killing '.$set.'-alarm');
		next unless ((defined $Alarm{$set}) and ($Alarm{$set}->{IsOn}));
		Glib::Source->remove($Alarm{$set}->{alarmhandle}) if (defined $Alarm{$set}->{alarmhandle});
		$Alarm{$set}->{alarmhandle} = undef;
		$Alarm{$set}->{IsOn} = 0;
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
