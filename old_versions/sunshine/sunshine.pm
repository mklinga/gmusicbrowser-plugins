# Gmusicbrowser: Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
# Sunshine: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
#
# This file is a plugin to Gmusicbrowser.
# It is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.


=gmbplugin SUNSHINE
name	Sunshine
title	Sunshine plugin
desc	For scheduling pleasant nights and sharp-starting mornings
=cut

package GMB::Plugin::SUNSHINE;
use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_SUNSHINE_',
};

use Gtk2::Notify -init, ::PROGRAM_NAME;
	use Data::Dumper;

my %button_definition=
(	class	=> 'Layout::Button',
	stock	=> 'plugin-sleep',
	tip	=> _"Enable sleep-mode",
	activate=> \&launch_sleepmode,
	autoadd_type	=> 'button main',
);
my %button_definition2=
(	class	=> 'Layout::Button',
	stock	=> 'plugin-sleep-alarm',
	tip	=> _"Enable sleep-mode with alarm",
	activate=> \&launch_both,
	autoadd_type	=> 'button main',
);
my %button_definition3=
(	class	=> 'Layout::Button',
	stock	=> 'plugin-alarm',
	tip	=> _"Set alarm",
	activate=> \&launch_alarmmode,
	autoadd_type	=> 'button main',
);

my %Sleepmode_type= #id => [name,cmd]
(	just_count => ["Just count"],
	just_time => ["Just time"],
	time_and_count => [_"Time AND count"],
	time_or_count => ["Time OR count"],
	immediate => ["Immediate sleep"],
	wait_for_queue => ["Sleep when queue empty"],
);



::SetDefaultOptions(OPT, timespan => 45,songcount => 12, sleepmode_type => 1, fading => 1, volume_goal => 25,
	wait_for_finish => 1, wakeup_mode => 1, relative_h => 8, relative_m => 0, fixed_h => 10, fixed_m => 0,
	listcheck => 0, repeat_alarm => 0, alarm_fade_min => 10, alarm_fade_from => 0, alarm_fade_to => 100,
	list_combo => 'list000', start_from_zero => 1, show_sleep_button => 1, show_sleepalarm_button => 1,
	show_alarm_button => 1, show_notifications => 1);

my $handle; my $alarm;
my $StartingVolume;
my $counter;
my $songcounter=0;
my $timespan=$::Options{OPT.'timespan'};
my $songgoal=$::Options{OPT.'songcount'};
my $sleeptype=$::Options{OPT.'sleepmode_type'};
my $fademode=$::Options{OPT.'fading'};
my $goalvolume=$::Options{OPT.'volume_goal'};
my $waitforfinish=$::Options{OPT.'wait_for_finish'};
my $timefinished=0;
my $countfinished=0;
my $waitingforfinishing=0;
my $volumemodifier=1;
my $countdown_started=0;
my $alarm_started=0;
my $m=0;my $s=0; my $h=0;
my @dayname= (_"Sun", _"Mon", _"Tue", _"Wed", _"Thu", _"Fri", _"Sat");

my $notify;
my ($Daemon_name,$can_actions,$can_body);

sub Start
{
	if ($::Options{OPT.'show_sleep_button'} == 1){Layout::RegisterWidget(SunshineSleep=>\%button_definition);}
	if ($::Options{OPT.'show_sleepalarm_button'} == 1){Layout::RegisterWidget(SunshineSleepAlarm=>\%button_definition2);}
	if ($::Options{OPT.'show_alarm_button'} == 1){Layout::RegisterWidget(SunshineAlarm=>\%button_definition3);}
	
	::Watch($handle, PlayingSong	=> \&Changed);
	$StartingVolume=::GetVol();
	$::Command{SleepMode}=[\&launch_both,_"Go to sleep",_"Timespan of the pre-sleep in minutes"];
	if ($::Options{OPT.'repeat_alarm'} == 1) { update_alarm(); }

}
sub Stop
{
	if ($::Options{OPT.'show_sleep_button'} == 1){Layout::RegisterWidget('SunshineSleep');}
	if ($::Options{OPT.'show_sleepalarm_button'} == 1){Layout::RegisterWidget('SunshineSleepAlarm');}
	if ($::Options{OPT.'show_alarm_button'} == 1){Layout::RegisterWidget('SunshineAlarm');}

	$notify = undef;
	::UnWatch($handle,'PlayingSong');
	Glib::Source->remove($handle) if $handle;	$handle=undef;
	Glib::Source->remove($alarm) if $alarm;		$alarm=undef;
	delete $::Command{SleepMode};
}


sub prefbox
{	my $vbox1=Gtk2::VBox->new;
	my $vbox2=Gtk2::VBox->new;
	my $vbox3=Gtk2::VBox->new;
	my $vbox4=Gtk2::VBox->new;
	my $sg1=Gtk2::SizeGroup->new('horizontal');

	my $spin=::NewPrefSpinButton(OPT.'timespan', 1,60*60*24, step=>1, text1=>_"Sleep in", text2=>_"minutes");
	my $spin2=::NewPrefSpinButton(OPT.'songcount', 1,1000, step=>1, text1=>_"/", text2=>_"songs");
	
	my %list= map {$_,$Sleepmode_type{$_}[0]} keys %Sleepmode_type;
	my $combo= ::NewPrefCombo (	OPT.'sleepmode_type', \%list,text=> _"Sleepmode type :",,sizeg1=>$sg1);
	
	my $volume_goal=::NewPrefSpinButton(OPT."volume_goal", 0,::GetVol(), step=>1,text1=>_" ", text2=>_"%");
	my $check=::NewPrefCheckButton(OPT."fading",'Fade volume during countdown to', , widget=>$volume_goal, horizontal=>1, sizegroup=>$sg1);
	my $check2=::NewPrefCheckButton(OPT."wait_for_finish",'Wait for last song to finish before stopping', horizontal=>1, sizegroup=>$sg1);
	my $notifycheck=::NewPrefCheckButton(OPT."show_notifications",'Show popup-notifications', horizontal=>1, sizegroup=>$sg1);
	
	my $entry=::NewPrefEntry(OPT.'CMD',_"Command to run when sleepmode activates :",	expand=>1,sizeg1=>$sg1);
	
	my $button=Gtk2::Button->new(_"Start sleep and alarm ");
	$button->signal_connect(clicked => \&launch_both);
	my $button4=Gtk2::Button->new(_"Start sleep-mode without alarm");
	$button4->signal_connect(clicked => \&launch_sleepmode);
	
	
	my $entry2=::NewPrefEntry(OPT.'wakeup_setting');
	my ($radio1a,$radio1b,$radio1c)=::NewPrefRadio(OPT.'wakeup_mode',undef,_"Relative time: ",0,_"Fixed time :",1,_"Fixed daily :",2);

	my $min_relative= ::NewPrefSpinButton(OPT."relative_m", 0,59, step=>1, page=>5, wrap=>1);
	my $hour_relative=::NewPrefSpinButton(OPT."relative_h", 0,23, step=>1, page=>4, wrap=>1);
	my $timeentry_relative=::Hpack($hour_relative,Gtk2::Label->new('hours'),$min_relative,Gtk2::Label->new('minutes after going to sleep'));
	
	my $min_fixed= ::NewPrefSpinButton(OPT."fixed_m", 0,59, step=>1, page=>5, wrap=>1);
	my $hour_fixed=::NewPrefSpinButton(OPT."fixed_h", 0,23, step=>1, page=>4, wrap=>1);
	my $timeentry_fixed=::Hpack(Gtk2::Label->new('exactly at '),$hour_fixed,Gtk2::Label->new(':'),$min_fixed);

	my @list2 = ::GetListOfSavedLists();
	my $listcombo= ::NewPrefCombo( OPT.'list_combo', \@list2);
	my $start_zero= ::NewPrefCheckButton(OPT."start_from_zero","Start from the first song in playlist");
	my $listcheck=::NewPrefCheckButton(OPT."listcheck",'Switch to playlist on wakeup: ', , widget=>$listcombo,horizontal=>1);

	my $repeatcheck=::NewPrefCheckButton(OPT."repeat_alarm",'Repeat alarm');
	#my $remembercheck=::NewPrefCheckButton(OPT."remember_alarm",'Remember alarm between sessions');

	my $button2=Gtk2::Button->new(_"Set alarm without sleep-mode");
	$button2->signal_connect(clicked => \&launch_alarmmode);

	my $button3=Gtk2::Button->new(_"Panic! Stop everything!");
	$button3->signal_connect(clicked => \&stop_everything);

	my $buttons_check1=::NewPrefCheckButton(OPT."show_sleep_button",'Show "Start Sleep"', horizontal=>1);
	my $buttons_check2=::NewPrefCheckButton(OPT."show_sleepalarm_button",'Show "Start Sleep & Alarm"', horizontal=>1);
	my $buttons_check3=::NewPrefCheckButton(OPT."show_alarm_button",'Show "Start Alarm"', horizontal=>1);

	my $preview= Label::Preview->new(preview => \&countdown_preview, event => 'CurSong Option', noescape=>1);
	my $preview2= Label::Preview->new(preview => \&alarm_preview, event => 'CurSong Option', noescape=>1);

	my @hours1;
	my @hours2;
	for my $wd (0..2)
	{	my $min= ::NewPrefSpinButton(OPT."day${wd}m", 0,59, step=>1, page=>5, wrap=>1);
		my $hour=::NewPrefSpinButton(OPT."day${wd}h", 0,23, step=>1, page=>4, wrap=>1);
		my $timeentry=::Hpack(Gtk2::Label->new($dayname[$wd]),$hour,Gtk2::Label->new(':'),$min);
		push @hours1,$timeentry;
	}
	for my $wd (3..6)
	{	my $min= ::NewPrefSpinButton(OPT."day${wd}m", 0,59, step=>1, page=>5, wrap=>1);
		my $hour=::NewPrefSpinButton(OPT."day${wd}h", 0,23, step=>1, page=>4, wrap=>1);
		my $timeentry=::Hpack(Gtk2::Label->new($dayname[$wd]),$hour,Gtk2::Label->new(':'),$min);
		push @hours2,$timeentry;
	}

	my $alarmfademin=::NewPrefSpinButton(OPT.'alarm_fade_min', 1,60*60*24, step=>1, text1=>_"", text2=>_"minutes");
	my $alarmfadefrom=::NewPrefSpinButton(OPT.'alarm_fade_from', 0,100, step=>1, text1=>_"from ", text2=>_"%");
	my $alarmfadeto=::NewPrefSpinButton(OPT.'alarm_fade_to', 0,100, step=>1, text1=>_"to ", text2=>_"%");
 
	my $alarmfadecheck=::NewPrefCheckButton(OPT."alarm_fade_check",'Fade volume in ');

	my $frame1=Gtk2::Frame->new(_"Going to sleep");
	my $frame2=Gtk2::Frame->new(_"Waking up");
	my $frame3=Gtk2::Frame->new(_"Info");
	my $frame4=Gtk2::Frame->new(_"Buttons");

	$vbox1=::Vpack( [$spin,$spin2],$check,$check2,$notifycheck,$combo,$entry );
	$vbox2=::Vpack( [$radio1a,$timeentry_relative],[$radio1b,$timeentry_fixed],$radio1c,[@hours1],[@hours2],[$repeatcheck,$listcheck,$start_zero],[$alarmfadecheck,$alarmfademin,$alarmfadefrom,$alarmfadeto] );
	$vbox3=::Vpack( $preview,$preview2 );
	$vbox4=::Vpack( [$buttons_check1,$buttons_check2,$buttons_check3] );

	$frame1->add($vbox1);
	$frame2->add($vbox2);
	$frame3->add($vbox3);
	$frame4->add($vbox4);

	return ::Vpack( $frame1,$frame2,$frame3,$frame4,[$button,$button4,$button2,$button3]);
	
}

sub Notify
{
	my ($notify_header, $notify_text) = @_;

	return 0 if ($::Options{OPT.'show_notifications'} == 0); 
	return 0 if ((not defined $notify_header) or (not defined $notify_text));
	
	if (not defined $notify)
	{
		$notify=Gtk2::Notify->new('empty','empty');
		my ($name, $vendor, $version, $spec_version)= Gtk2::Notify->get_server_info;
		$Daemon_name= "$name $version ($vendor)";
		my @caps = Gtk2::Notify->get_server_caps;
		$can_body=	grep $_ eq 'body',	@caps;
		$can_actions=	grep $_ eq 'actions',	@caps;
	}

	$notify->update($notify_header,$notify_text);
	$notify->set_timeout(4000);
	eval{$notify->show;};
	if ($@){warn "Sunshine ERROR: \$notify didn't evaluate properly!";};
	
	return 1;
}

sub stop_everything
{
	$countdown_started=0;
	$alarm_started=0;	
	Glib::Source->remove($handle) if $handle;	
	$handle=undef;
	Glib::Source->remove($alarm) if $alarm; 
	$alarm=undef;	
	Notify('Sunshine','Sleep-mode and alarm have been disabled.');
	
	
}

sub countdown_preview
{	
	my $text='';
	
	if ($countdown_started==1) {
		$text = "Countdown in progress: ".int($counter/60)." of ".int($timespan/60)." minutes ~ ".$songcounter." of ".$songgoal." songs\n";
	}
	elsif ($countdown_started==0) {
		$text = "No countdown set.\n";
	}
	return $text;
}

sub alarm_preview
{	
	my $text="";
	
	if (($alarm_started==1) and ($alarm)) {
		$text = "Alarm is enabled at ".($h).":".($m).":".($s);
	}
	elsif (($alarm_started==1) and !($alarm)) {
		$text = "Alarm is enabled (No alarm-handle! Wat!) at ".($h).":".($m).":".($s);
	}
	elsif ($alarm_started==0) {
		$text = "Alarm is disabled.";
	}

	return $text;
}

sub Changed
{
	$songcounter = $songcounter+1;
	if ($waitingforfinishing==1)
	{
		#enough wait, let's shut down when possible
		$waitingforfinishing=2;
	}

	if (($sleeptype eq 'wait_for_queue') and (@$::Queue == 0) and ($countdown_started==1))
	{
		if ($waitingforfinishing != 2) { $waitingforfinishing = 1;}
		elsif ($waitingforfinishing == 2){finished();}
	}
}

sub start_notification
{
	my $notify_header;
	my $notify_text;

	if (($alarm_started==0) and ($countdown_started==1))
	{
		$notify_header = "Sleepmode activated";
		
		if (($sleeptype eq 'just_time') and ($timefinished == 1)){$notify_text = "Going to sleep in ".($timespan/60)." minutes";}
		elsif (($sleeptype eq 'just_count') and ($countfinished == 1)){$notify_text = "Going to sleep after ".$songgoal." songs";}
		elsif ($sleeptype eq 'time_and_count'){if (($timefinished==1) and ($countfinished==1)){$notify_text = "Going to sleep after ".($timespan/60)." minutes and ".$songgoal." songs";}}
		elsif ($sleeptype eq 'time_or_count'){if (($timefinished==1) or ($countfinished==1)){$notify_text = "Going to sleep in ".($timespan/60)." minutes or after ".$songgoal." songs";}}
		elsif ($sleeptype eq 'immediate'){$notify_text = "Going to sleep NOW!";}
		elsif ($sleeptype eq 'wait_for_queue'){	$notify_text = "Going to sleep when queue ends";}
		else {$notify_text = 'Going to sleep... sometime';}
		
	}
	elsif (($alarm_started==1) and ($countdown_started==1))
	{
		$notify_header = "Sleepmode with Alarm activated";

		if (($sleeptype eq 'just_time') and ($timefinished == 1)){$notify_text = "Going to sleep in ".($timespan/60)." minutes\nWaking up at ".($h).":".($m).":".($s);}
		elsif (($sleeptype eq 'just_count') and ($countfinished == 1)){	$notify_text = "Going to sleep after ".$songgoal." songs\nWaking up at ".($h).":".($m).":".($s);}
		elsif ($sleeptype eq 'time_and_count'){if (($timefinished==1) and ($countfinished==1)){$notify_text = "Going to sleep after ".($timespan/60)." minutes and ".$songgoal." songs\nWaking up at ".($h).":".($m).":".($s);}}
		elsif ($sleeptype eq 'time_or_count'){if (($timefinished==1) or ($countfinished==1)){$notify_text = "Going to sleep in ".($timespan/60)." minutes or after ".$songgoal." songs\nWaking up at ".($h).":".($m).":".($s);}}
		elsif ($sleeptype eq 'immediate'){$notify_text = "Going to sleep NOW!\nWaking up at ".($h).":".($m).":".($s);}
		elsif ($sleeptype eq 'wait_for_queue'){	$notify_text = "Going to sleep when queue ends\n"."Waking up at ".($h).":".($m).":".($s);}
		else { $notify_text = "Going to sleep... sometime\n"."Waking up at ".($h).":".($m).":".($s);}
	}
	elsif (($alarm_started==1) and ($countdown_started==0))
	{
		$notify_header = 'Alarm activated';
		$notify_text = "Waking up at ".($h).":".($m).":".($s);
	}
	else
	{
		$notify_header = 'Sunshine';
		$notify_text = 'This notification is quite a mystery...';
	}
	
	Notify($notify_header, $notify_text);
	
}

sub update_alarm
{	

	Glib::Source->remove($alarm) if $alarm; $alarm=undef;
	
	$alarm_started=1;

	my $now=time;
	my ($s0,$m0,$h0,$mday0,$mon,$year,$wday0,$yday,$isdst)= localtime($now);
	my $next=0;
	my $time;
		
	my $wakeupmode=$::Options{OPT.'wakeup_mode'};
		
	$m=0;
	$h=0;
	$s=0;
			
	if ($wakeupmode == 0)
	{
		$m=($m0+$::Options{OPT.'relative_m'})%60;
		$h=($h0+$::Options{OPT.'relative_h'})%24;
		$s=$s0;
		$time=::mktime($s,$m,$h,$mday0,$mon,$year);
		$time=::mktime($s,$m,$h,($mday0+1)%7,$mon,$year) if $time<=$now;
		$next=$time;
	}
	elsif ($wakeupmode == 1)
	{
		#one-time fixed
		$m=$::Options{OPT.'fixed_m'};
		$h=$::Options{OPT.'fixed_h'};
		$time=::mktime($s,$m,$h,$mday0,$mon,$year);
			$time=::mktime($s,$m,$h,($mday0+1)%7,$mon,$year) if $time<=$now;
		$next=$time;
		
	}
	elsif ($wakeupmode == 2)
	{
		#fixed daily
		for my $wd (0..6)
		{	
		
			my $mday=$mday0+($wd-$wday0+7)%7;
			my $m2=$::Options{OPT."day${wd}m"};
			my $h2=$::Options{OPT."day${wd}h"};
			$time=::mktime($s,$m2,$h2,$mday,$mon,$year);
			$time=::mktime(0,$m2,$h2,$mday+7,$mon,$year) if $time<=$now;
			if ($next) 
			{
				if ($time<$next)
				{
					$m = $m2;
					$h = $h2;
					$next = $time;
				}
			}
			else 					
			{
					$m = $m2;
					$h = $h2;
					$next = $time;
			}
		}
	}

	return unless $next;
	$alarm=Glib::Timeout->add(($next-$now)*1000,\&alarm);

}
sub fade_alarm
{
	if (::GetVol() < $::Options{OPT.'alarm_fade_to'})
	{
		my $new= ::GetVol() + 1;
		$new=::GetVol() if $new>$::Options{OPT.'alarm_fade_to'};
		::UpdateVol($new);
	}
	else 
	{
		#fade complete, remove handle
		Glib::Source->remove($handle) if $handle;	
		$handle=undef;
	}
	return $handle; #false when finished
	

}
sub alarm 
{ 
	#don't start alarm if music is already playing (e.g. manual input)
	if (not ((defined $::TogPlay) and ($::TogPlay == 1)))
	{
		if ($::Options{OPT.'alarm_fade_check'}==1)
		{
			my $a_from = $::Options{OPT.'alarm_fade_from'};
			my $a_to = $::Options{OPT.'alarm_fade_to'};
			my $a_timespan = $::Options{OPT.'alarm_fade_min'}*60;

			if ($a_from > $a_to) { return; }#don't handle fading down
			else
			{
				Glib::Source->remove($handle) if $handle;	
				$handle=undef;
			
				::UpdateVol($a_from);
				my $timething = int(($a_timespan)/($a_to-$a_from)*1000);
				$handle=Glib::Timeout->add($timething,\&fade_alarm,1);
			}
		}
		start_wakemode();
	}
	 
	$alarm_started=0;

	if ($::Options{OPT.'repeat_alarm'} == 1) {
		update_alarm();
	}
}

sub start_wakemode
{
	if ($::Options{OPT.'listcheck'} == 1)
	{
		if (!($::Options{OPT.'list_combo'} eq ""))
		{
			::Select( staticlist => $::Options{OPT.'list_combo'} );
			if ($::Options{OPT."start_from_zero"} == 1){::SetPosition(0);}
			::Play;
		}
	}
	else
	{
		::PlayPause;
	}
}
sub launch_both
{
	start_sleepmode();
	update_alarm();
	start_notification();	
}
sub launch_sleepmode
{
	start_sleepmode();
	start_notification();
}
sub launch_alarmmode
{
	update_alarm();
	start_notification();	
}

sub start_sleepmode
{	return if $handle;
	
	$countdown_started=1;
	
	$timespan=$::Options{OPT.'timespan'};
	$songgoal=$::Options{OPT.'songcount'};
	$sleeptype=$::Options{OPT.'sleepmode_type'};
	$fademode=$::Options{OPT.'fading'};
	$goalvolume=$::Options{OPT.'volume_goal'};
	$waitforfinish=$::Options{OPT.'wait_for_finish'};
	
	if ($::Options{OPT.'sleepmode_type'} eq 'Immediate sleep')
	{
		$timefinished=1;
		$countfinished=1;
		$waitingforfinishing=2;
	}
	else
	{
		$timefinished=0;
		$countfinished=0;
	}
	$timespan=$timespan*60;

	if ($waitforfinish == 0)
	{
		#let's finish immediately when possible ('wait for last song to end' not set)
		$waitingforfinishing = 2;
	}
	else 
	{
		$waitingforfinishing=0;
	}
	
	
	if ($fademode==1)
	{
		$StartingVolume= ::GetVol();
		if ($StartingVolume <= $goalvolume)
		{
			#never update (FIX: update?)
			$volumemodifier=$timespan+1;
		}
		else
		{
			$volumemodifier=int($timespan/($StartingVolume-$goalvolume));
		}
	}
	else
	{
		$volumemodifier=1;
	}

	
	$counter=0;
	$songcounter=0;
	
	$handle=Glib::Timeout->add(1000,\&check_if_finished,1);
}
sub check_if_finished
{	
	$counter = $counter +1;
	
	if ($fademode==1)
	{
		if(($counter%$volumemodifier == 0) and ($goalvolume<::GetVol()))
		{
			my $new= ::GetVol() - 1;
			$new=$goalvolume if $new<$goalvolume;
			::UpdateVol($new);
		}
	}
	if (($sleeptype ne 'wait_for_queue') and ($counter>=$timespan))
	{	
		if ($waitingforfinishing==0)
		{
			#this goes from 1 to 2 when song changes
			$waitingforfinishing=1;
		}
		elsif ($waitingforfinishing==2)
		{
			$timefinished = 1;
		}
	}
	elsif (($sleeptype eq 'wait_for_queue') and ($counter>=$timespan))
	{
			$timefinished = 1;
	}
	
	if ($songcounter>$songgoal)
	{
		$countfinished = 1;		
	}
	
	
	if (($sleeptype eq 'just_time') and ($timefinished == 1))
	{
		finished();
	}
	elsif (($sleeptype eq 'just_count') and ($countfinished == 1))
	{
		finished();
	}
	elsif ($sleeptype eq 'time_and_count')
	{
		if (($timefinished==1) and ($countfinished==1))
		{
			finished();
		}
	}
	elsif ($sleeptype eq 'time_or_count')
	{
		if (($timefinished==1) or ($countfinished==1))
		{
			finished();
		}
	}
	elsif ($sleeptype eq 'immediate')
	{
		finished();
	}
	
	return $handle; #false when finished
}

sub finished 
{
	$countdown_started=0;
	warn "going to sleep NOW!\n";

	$handle=undef;
	::PlayPause();
	::UpdateVol($StartingVolume);
	update_alarm();
	my $cmd= $::Options{OPT.'CMD'};
	return unless defined $cmd;
	my @cmd= ::split_with_quotes($cmd);
	return unless @cmd;
	::forksystem(@cmd);

	#print "Updating alarm once more 'cause of shutdown...\n";
	sleep(10);
	update_alarm();

}

1
