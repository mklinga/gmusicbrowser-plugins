# Copyright (C) 2005-2009 Quentin Sculo <squentin@free.fr>
#
# This file is part of Gmusicbrowser.
# Gmusicbrowser is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation

# the plugin file must have the following block before the first non-comment line,
# it must be of the format :
# =gmbplugin PID
# name	short name
# title	long name, the short name is used if empty
# desc	description, may be multiple lines
# =cut
=gmbplugin ALBUMRANDOM
name	Albumrandom
title	AlbumRandom plugin
desc	Albumrandom plays albums according to set weighted random. Use context menu to choose albums to play.
=cut

# the plugin package must be named GMB::Plugin::PID (replace PID), and must have these sub :
# Start	: called when the plugin is activated
# Stop	: called when the plugin is de-activated
# prefbox : returns a Gtk2::Widget used to describe the plugin and set its options

package GMB::Plugin::ALBUMRANDOM;
use strict;
use warnings;

use constant
{	OPT	=> 'PLUGIN_ALBUMRANDOM_',
};

use Gtk2::Notify -init, ::PROGRAM_NAME;

::SetDefaultOptions(OPT, play_immediately => 0);
::SetDefaultOptions(OPT, infinite => 1);
::SetDefaultOptions(OPT, export => 0);
::SetDefaultOptions(OPT, return_playmode_after_album => 1);
::SetDefaultOptions(OPT, only_top => 1);
::SetDefaultOptions(OPT, only_top_nb => "100");
::SetDefaultOptions(OPT, use_cache => 1);
::SetDefaultOptions(OPT, store_cache => 0);
::SetDefaultOptions(OPT, follow_filter => 0);
::SetDefaultOptions(OPT, show_notifications => 0);


my $ON;
my $IDs;


my %button_definition=
(	class	=> 'Layout::Button',
	stock	=> 'plugin-albumrandom',
	tip	=> "Choose an album for me!",	click1	=> \&CalculateButton,
	click3	=> \&ToggleInfinite,
	#activate=> \&CalculateButton,
	autoadd_type	=> 'button main',
);

my %menuentry=
( tom3u =>
 {	label => _"Choose an album for me!",
	code => \&ChooseSourceAndCalculate,
	notempty => 'IDs',
 },
 selectsource =>
 {
 	label => "Select as AR source",
 	code => \&ChooseSource,
 	notempty => 'IDs',
 }
);

my %FLmenuentry=
(tom3u =>
 {	label => _"Choose an album for me!",
	code => \&ChooseSourceAndCalculate,
	isdefined => 'filter',
 },
 selectsource =>
 {
 	label => "Select as AR source",
 	code => \&ChooseSource,
 	isdefined => 'filter',
 }
);

my $Cachefile = $::HomeDir.'albumcache.save';
my $Datafile = $::HomeDir.'albumstats';

my $notify;
my ($Daemon_name,$can_actions,$can_body);

my $notify_header = "Albumrandom";
my $notify_text = "";

my $handle;
my $handle2;
my $autocalculate = 0;
my $current_last_ID = -1;
my $current_artistalbum = '';
my $current_item = -1;
my $text='';

my @data_song_prob;
my @data_album_prob;
my @data_album_aa;
my @data_album_first;
my @data_album_last;

my $first_time;
my $force_db_update = 0;
my $button_text = "Calculate database now (resets currently playing album)";

my @songtaulu;

my $alarm;
my $alarm_started=0;
my $lastupdate='DB not updated in this session.';
my $nextupdate="   No automatic update set";

my $content;
my @needsupdate;
my $update_on_change = 0;
my $update_item=-1;

my $startup = 1;


sub Start
{
	my $self=shift;
	srand(time);
	
	Layout::RegisterWidget(Albumrandom=>\%button_definition);
	
	$ON=1;
	$first_time = 1;
	
	$IDs=$::SelectedFilter->filter;
	#print ("Filter : ".scalar@$array." | ".$::SelectedFilter->explain);	

	$notify=Gtk2::Notify->new('empty','empty');
	my ($name, $vendor, $version, $spec_version)= Gtk2::Notify->get_server_info;
	$Daemon_name= "$name $version ($vendor)";
	my @caps = Gtk2::Notify->get_server_caps;
	$can_body=	grep $_ eq 'body',	@caps;
	$can_actions=	grep $_ eq 'actions',	@caps;

	if ($::Options{OPT.'update_automatically'} == 1){ settimedupdate();}
	
	updatemenu();
	$handle={};	#the handle to the Watch function must be a hash ref, if it is a Gtk2::Widget, UnWatch will be called when the widget is destroyed
	::Watch($handle, PlayingSong	=> \&Changed);
	::Watch($handle2, Filter	=> \&updateFilter);

}
sub Stop
{	$ON=0;
	$notify=undef;
	updatemenu();
	Layout::RegisterWidget('Albumrandom');
	::UnWatch($handle,'PlayingSong');
	Glib::Source->remove($alarm) if $alarm;		$alarm=undef;
	
}

sub prefbox
{	my $vbox= Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	
	my $check=::NewPrefCheckButton(OPT."play_immediately",'Start playing immediately', horizontal=>1, sizegroup=>$sg1);
	my $check2=::NewPrefCheckButton(OPT."infinite",'Infinite Mode', horizontal=>1, sizegroup=>$sg1);
	my $check3=::NewPrefCheckButton(OPT."export",'Export stats to \'~/.config/gmusicbrowser/albumstats\'', horizontal=>1, sizegroup=>$sg1);
	my $check4=::NewPrefCheckButton(OPT."return_playmode_after_album",'Switch to Random mode after album is played (Only when Infinite mode is disabled)', horizontal=>1, sizegroup=>$sg1);
	my $check5=::NewPrefCheckButton(OPT."use_cache",'Use cached data whenever possible', horizontal=>1, sizegroup=>$sg1);
	my $check6=::NewPrefCheckButton(OPT."store_cache",'Store cache between sessions [NOT RECOMMENDED]', horizontal=>1, sizegroup=>$sg1);
	my $check8=::NewPrefCheckButton(OPT."show_notifications",'Show notifications', horizontal=>1, sizegroup=>$sg1);
	my $check9=::NewPrefCheckButton(OPT."follow_filter",'Source follows playlist filter changes', horizontal=>1, sizegroup=>$sg1);

	my $time_spin=::NewPrefSpinButton(OPT."hour", 0,23, step=>1, page=>4, wrap=>1, cb=>\&Updateprefchange);
	my $time_entry=::Hpack($time_spin,Gtk2::Label->new(' hours'));
	my $check7=::NewPrefCheckButton(OPT."update_automatically",'Update automatically every',cb=>\&Updateprefchange, widget=>$time_entry,horizontal=>1);
	
	my $top_nb=::NewPrefSpinButton(OPT."only_top_nb", 2,5000, step=>1,text1=>_" ", text2=>_" albums");
	my $topcheck=::NewPrefCheckButton(OPT."only_top",'Select only from top ', , widget=>$top_nb, horizontal=>1);

	my $button=Gtk2::Button->new();
	$button->signal_connect(clicked => \&Recalculate);
	$button->set_label($button_text);

	my $frame1=Gtk2::Frame->new(_"Options");
	
	my $lastlabel=Gtk2::Label->new();
	$lastlabel->set_label($lastupdate);
	my $nextlabel=Gtk2::Label->new();
	$nextlabel->set_label($nextupdate);

	my $l2=Gtk2::Label->new();
	$l2->set_label("Current source: ".scalar@$IDs." items ");
	
	$vbox=::Vpack( [$check2,$check],[$check3,$check4],[$check5,$check6],[$check8,$check7],[$check9,$topcheck],[$lastlabel,$nextlabel,$l2,$button] );
	$frame1->add($vbox);
	
	return ::Vpack( $frame1);
	
}

sub updateFilter
{
	if ($::Options{OPT.'follow_filter'} == 1)
	{
		$IDs=$::SelectedFilter->filter;
		if (($::Options{OPT.'show_notifications'}) == 1 && ($startup != 1))
		{
			$notify_text = "Changed source to match playlist filter\nItems in filter: ".scalar@$IDs;
	
			$notify->update($notify_header,$notify_text);
			$notify->set_timeout(4000);
			$notify->show;
		}
		$startup = 0;
	}
		#print "Yep.";
}

sub ToggleInfinite
{
	if ($::Options{OPT.'infinite'} == 0) { $::Options{OPT.'infinite'} = 1 }else{ $::Options{OPT.'infinite'} = 0;}
	
	if ($::Options{OPT.'show_notifications'} == 1)
	{
		if ($::Options{OPT.'infinite'} == 1){$notify_text = "Infinite Mode is: ON";}
		else{$notify_text = "Infinite Mode is: OFF";	}
	
		$notify->update($notify_header,$notify_text);
		$notify->set_timeout(4000);
		$notify->show;
	}
	
}
sub settimedupdate
{

	Glib::Source->remove($alarm) if $alarm; $alarm=undef;
	
	$alarm_started=1;

	my $now=time;
	my ($s0,$m0,$h0,$mday0,$mon,$year,$wday0,$yday,$isdst)= localtime($now);
	
	my $next=0;
	my $time;
		
	my $h=0;
			
	$h=($h0+$::Options{OPT.'hour'})%24;

	$time=::mktime($s0,$m0,$h,$mday0,$mon,$year);
	if ($time <= $now)
	{
		$time += 86400;
		($s0,$m0,$h0,$mday0,$mon,$year,$wday0,$yday,$isdst)= localtime($time);
	}
	$next=$time;

	return unless $next;
	$alarm=Glib::Timeout->add(($next-$now)*1000,\&timer);
	
	
	$nextupdate="   Automatic update: ".$mday0.".".($mon+1).".".($year+1900)."  ".sprintf("%02d",$h).":".sprintf("%02d",$m0).":".sprintf("%02d",$s0)."   ";

	if ($::Options{OPT.'show_notifications'} == 1)
	{
		$notify_text = "Automatic update in ".$::Options{OPT.'hour'}." hours";
		$notify->update($notify_header,$notify_text);
		$notify->set_timeout(4000);
		$notify->show;
	}
}

sub updatemenu
{	my $removeall=!$ON;
	for my $eid (keys %menuentry)
	{	my $menu=\@::SongCMenu;
		my $entry=$menuentry{$eid};
		if (!$removeall )
		{	push @$menu,$entry unless (grep $_==$entry, @$menu);
		}
		else
		{	@$menu =grep $_!=$entry, @$menu;
		}
	}
	for my $eid (keys %FLmenuentry)
	{	my $menu=\@FilterList::FLcMenu;
		my $entry=$FLmenuentry{$eid};
		if (!$removeall)
		{	push @$menu,$entry unless (grep $_==$entry, @$menu);
		}
		else
		{	@$menu =grep $_!=$entry, @$menu;
		}
	}

}

sub Updateprefchange
{
	if ($::Options{OPT.'update_automatically'} == 1) 
	{
	  settimedupdate;	
	}
	else
	{
		$nextupdate="   No automatic update set";
	}
	
}

sub ExportStats
{
	$content="#Albumstats\nIDtaulu:";
	foreach my $ab (@data_album_first) {	$content.= " $ab"; }
	$content .= "\nLastIDs: ".scalar@data_album_first;
	$content .= "\nProbtaulu:";
	my $c=0;
	my $avg=0;
	foreach my $ab (@data_album_prob) 
	{ 
		$avg += $ab;
		$c++;
		$content.= " $ab"; 
	}
	
	$content .= "\nTotal: ".$c." albums,"." Avg: ".sprintf("%.3f",($avg/$c));	
	$content .= "\nAlbums:\n";
	for (my $a=0;$a<scalar@data_album_aa;$a++)
	{
		$content .= $data_album_aa[$a].sprintf("%.3f",$data_album_prob[$a])."\n";
	}
	
}

sub CalculateAlbum
{
	
	return 'non- IDs' unless @$IDs;

	#meillä on kaksi taulua, joiden [id]:t täsmäävät
	#valitaan satunnaisesti, kunnes natsaa

	my $isOK = 0;
	my $counter = 0;
	my $number = 0;
	my $curitem;
	my $item;
	my $totalprob=0;
	my @topalbums = ();
	my $topamount;
	my @topprob = ();
	my @topid = ();

	if ($::Options{OPT.'only_top'} == 1)
	{
		$topamount = $::Options{OPT.'only_top_nb'};
		my $count = 0;
		foreach my $it (@data_album_prob)
		{
			my $topid = sprintf("%.5f",$it)."|||".$data_album_first[$count];
			push (@topalbums,$topid);
			$count++;
		}
		
		@topalbums = sort @topalbums;

		if (scalar@topalbums < $topamount) { $topamount = scalar@topalbums;}
		
		for (my $i=0;$i<$topamount;$i++)
		{
			my $brk = (rindex $topalbums[scalar@topalbums-($i+1)],"|||");
			push(@topprob,substr($topalbums[scalar@topalbums-($i+1)],0,$brk));
			push(@topid,substr($topalbums[scalar@topalbums-($i+1)],$brk+3));
			#print Songs::Get($topid[$i],qw/album/)." : ".$topprob[$i]."\n";	
		}
		foreach my $tp (@topprob) { $totalprob += $tp; }

		#print "Top".scalar@topid.":\n1. ".Songs::Get($topid[0],qw/album/)."\n2. ".Songs::Get($topid[1],qw/album/)."\n3. ".Songs::Get($topid[2],qw/album/)."\n";

	}
	else
	{
		foreach my $tp (@data_album_prob) { $totalprob += $tp; }
	}

	while (($isOK == 0) && ($counter < 500))
	{
		$counter++;
		$number = rand()*$totalprob; # 0<$number<totalprob
		my $temp = 0;
		$item = -1;
		while ($temp < $number)
		{
			$item++;
			if ($::Options{OPT.'only_top'} == 1) {$temp += $topprob[$item];}
			else {$temp += $data_album_prob[$item];}
		}
		if (($::Options{OPT.'only_top'} == 1) && ($topid[$item] != $data_album_first[$current_item])) { $isOK = 1;}
		elsif (($item) != $current_item) { $isOK = 1;}
	}		

	if ($::Options{OPT.'only_top'} == 1) 
	{
		#change $item according to the whole table!
		my $found = 0;
		my $count = 0;
		while (($found == 0) && $count < scalar@data_album_first)
		{
			if ($data_album_first[$count] == $topid[$item]) { $found = 1; $item = $count;}
			$count++; 
			
		}
	}

	$content .= "\n### Randomizer: ".$item.". ".$data_album_aa[$item]." - ".sprintf("%.3f",$number)."/".sprintf("%.3f",$totalprob)."(".sprintf("%.3f",$data_album_prob[$item]).")\n";
	
	my ($aa,$da,$ca)= Songs::Get($data_album_first[$item],qw/album_artist year album/);
	
	$current_artistalbum = $aa.$da.$ca;

	#print("Item: ".$item." Number: ".$number." Songid:".$idtaulu[$item]." prob:".$probtaulu[$item]);
	my $filt = Songs::MakeFilterFromID('album',$data_album_first[$item]);
	
	#let's go back to normal!
	::ToggleSort if ($::RandomMode);
	::Enqueue($data_album_first[$item]);
	
	if (($autocalculate == 0) && ($::Options{OPT.'play_immediately'} ==1)) 
	{
		::NextSong; 
		::Play;
	}
	#if nothing is playing let's move to next song immediately and wait
	elsif (!(defined $::TogPlay)) {::NextSong;} 
	

	$current_last_ID = $data_album_last[$item];
	$current_item = $item;

    if ($::Options{OPT.'export'} == 1)
    {
	
		return 'no datafile' unless defined $Datafile;

		open my $fh,'>',$Datafile or warn "Error opening '$Datafile' for writing : $!\n";
		print $fh $content   or warn "Error writing to '$Datafile' : $!\n";
		close $fh;

    }
	return 1;

}

sub CalculateDB
{

	if (scalar@$IDs == 1){return "Can't make random album from one track!";	}
	
	::ToggleSort if !($::RandomMode);

	#my @songcache;
	#my @probcache;
	#my @idcache;
	#my @aacache;
	#if ($::Options{OPT.'use_cache'} == 1)
	#{
	#	push (@probcache,@probtaulu);
	#	push (@idcache,@idtaulu);
	#	push (@congcache,@songtaulu);
	#	push (@aacache,@aataulu);
	#}

    #empty tables
	@songtaulu = ();
	@needsupdate = ();
	
	@data_album_aa = ();
	@data_album_first = ();
	@data_album_last = ();
	@data_album_prob = ();

	if ($first_time == 1)
	{

		#no data anywhere at the first time, unless 'store cache' option in place - let's check it out!
		my $cacheLoaded = 0;
		if ($::Options{OPT.'store_cache'} == 1)
		{

			if (defined $Cachefile)
			{
				open my $fh,'<',$Cachefile or $cacheLoaded = -1;
				
				if ($cacheLoaded != -1)
				{
					my @lines = <$fh>;
					close($fh);
				
					foreach my $line (@lines)
					{
						chomp($line);
						push(@data_song_prob,$line);	
					}

					# There might be some new IDs so we must expand table with -1's
					my $biggest=-1;
					foreach my $id (@$IDs) { if ($id > $biggest) { $biggest = $id;}}
					for (my $i=scalar@data_song_prob; $i<($biggest+1);$i++) { push (@data_song_prob,-1);}


					$cacheLoaded = 1;
					print "Albumrandom: cache loaded successfully (".scalar@data_song_prob." items)\n";
				}
				else { $cacheLoaded = 0; print "Couldn't open $Cachefile";}
			}
			else {} 			
		}
		
		if ($cacheLoaded == 0)
		{
			# No cache -> let's find biggest ID and assign all prob's to -1
			my $biggest=-1;
			foreach my $id (@$IDs) { if ($id > $biggest) { $biggest = $id;}}
			for (my $i=0; $i<($biggest+1);$i++) { push (@data_song_prob,-1);}
		}
		$first_time = 0;
	}

	for (my $counter=0;$counter<scalar@$IDs;$counter++)
	{
		my ($artist,$album,$date,$track)= Songs::Get(@$IDs[$counter],qw/album_artist album year track/);
		$text=$artist." - (".$date.") ".$album." : ".sprintf("%3d",$track)."|||".@$IDs[$counter];
		
		if (($force_db_update == 1) || ($::Options{OPT.'use_cache'} == 0))#no cache or force_update => calculate everything.
		{
			$data_song_prob[@$IDs[$counter]] = $::RandomMode->CalcScore(@$IDs[$counter]);
		}
		elsif (($data_song_prob[@$IDs[$counter]] == -1) && ($::Options{OPT.'use_cache'} == 1))
		{
			$data_song_prob[@$IDs[$counter]] = $::RandomMode->CalcScore(@$IDs[$counter]);
		}
		push(@songtaulu,$text);
	}
	
	@songtaulu = sort @songtaulu;
	# biisit on järjestettyinä muodossa: artist - (date) album : track|||id 

	my $oldaa = '';
	my $oldsongid = '';
	my $count = 0;
	my $totalcounter = 0;
	my $item;
	my $albumprob = 0;
	my $oldlastid;
	
	foreach $item (@songtaulu)
	{
		my $songid = substr($item,(rindex $item,"|||")+3,(length($item)-(rindex $item,"|||")-2));
		#print $songid;
		my $aa=substr($item,0,(rindex $item,"|||")-3);
		my $prob = $data_song_prob[$songid];
		$count++;
		$totalcounter++;
		
		if ($aa eq $oldaa)
		{
			#same aa than previous <=> same album than previous
			$albumprob += $prob;
			$data_album_last[(scalar@data_album_last)-1] = $songid;
			
			#if last item in the table -> close album
			if ($totalcounter == scalar@songtaulu)
			{
				push(@data_album_prob,($albumprob/$count));
				#print "AA:".$aa." Prob: ".$prob." totprob: ".$albumprob." cnt: ".$count."\n";
			}
		}
		else
		{
			if ($oldaa eq '')
			{
				#first item
				$albumprob = $prob;
				$oldaa = $aa;
				push (@data_album_first, $songid);
				push (@data_album_last, $songid);
				push(@data_album_aa,$aa);
			}
			else
			{
				#change of album, current $item, $prob are from next album!
				#closing album has ($count-1) items
				push(@data_album_prob,($albumprob/($count-1)));

				#then let's handle the new album
				$count = 1;
				$albumprob = $prob;
				$oldaa = $aa;				
				push (@data_album_first, $songid);
				push (@data_album_last, $songid);
				push(@data_album_aa,$aa);
			}
		}
	}
	
	#export cache if wanted
	if ($::Options{OPT.'store_cache'} == 1)
	{
		open my $fh,'>',$Cachefile or warn "Error opening '$Cachefile' for writing : $!\n";
		foreach my $prob (@data_song_prob)
		{
			print $fh $prob."\n" or warn "Error writing to '$Cachefile' : $!\n";
		}
		close $fh;
		print "Albumrandom: cache stored (".scalar@data_song_prob." items)\n";
	}

	$button_text = "Re-calculate data now (resets currently playing album)";

	my $now=time;
	my ($s,$m,$h,$mday,$mon,$year,undef,undef,undef)= localtime($now);
	
	$lastupdate="DB updated ".$mday.".".($mon+1).".".($year+1900)."  ".sprintf("%02d",$h).":".sprintf("%02d",$m).":".sprintf("%02d",$s)." ";

	$force_db_update = 0;

	return 1;	
}

sub CalculateUpdate
{
	#This only updates album that was selected for albumrandom, when the last song is played!
	#Shouldn't be any songs that are not from $current_item!!

	return "No \$current_item!" unless $update_item >= 0;
	
	return "No need for updating" unless @needsupdate;
	return unless @$IDs;
	
	my @finalupdates = ();
	
	foreach my $updateID (@needsupdate)
	{
		my $alb=Songs::Get_gid($updateID,'album');
		my $l=AA::GetIDs('album',$alb);

	  	push (@finalupdates,@$l);
	}		

	#remove duplicates with hash
	my %hash   = map { $_, 1 } @finalupdates;
	@finalupdates = keys %hash;

	my $count = 0;
	my $totalprob = 0;

	my $sort_chg=0;
	if (!($::RandomMode)) {$sort_chg=1; ::ToggleSort;}
	
	foreach my $usID (@finalupdates)
	{
		my ($uaa,$ud,$ual) = Songs::Get($usID,qw/album_artist year album/);
		my $u = $uaa." - (".$ud.") ".$ual;
		my $dest = substr($data_album_aa[$update_item],0,length($u));
		
		if (!($u eq $dest)) { warn "current_item and needsupdate doesn't match :("; last;}
		else
		{
			#täsmää, päivitetään
			$data_song_prob[$usID] = $::RandomMode->CalcScore($usID);
			$totalprob += $data_song_prob[$usID];
			$count++;
		}
	}

	if ($sort_chg == 1) {::ToggleSort;}
	
	return "couldn't update" unless $count > 0;

	$notify_text = "CalculateUpdate successful! (with ".$count." items)";
	$notify->update($notify_header,$notify_text);
	$notify->set_timeout(4000);
	$notify->show;
	$data_album_prob[$update_item] = $totalprob/$count;

	return 1;
	
}

sub timer
{
	#time to update!
	return "no IDs for timed update!" unless @$IDs;

	if ($::Options{OPT.'show_notifications'} == 1)
	{
		$notify_text = "Starting automatic update...";
	
		$notify->update($notify_header,$notify_text);
		$notify->set_timeout(4000);
		$notify->show;
	}

	
	$force_db_update = 1;
	CalculateDB;

	if ($::Options{OPT.'update_automatically'} == 1) 
	{
	  settimedupdate;	
	}
	else
	{
		$nextupdate="   No automatic update set";
	}

	return 1;
}

sub Recalculate
{
	return "no IDs" unless @$IDs;
	
	$force_db_update = 1;
	CalculateDB;
	return 1;
}

sub ChooseSource
{
	$IDs=$_[0]{IDs} || $_[0]{filter}->filter;
	return unless @$IDs;
	$startup = 0;
		
	if ($::Options{OPT.'show_notifications'} == 1)
	{
		$notify_text = "New source selected\nItems: ".scalar@$IDs;
		$notify->update($notify_header,$notify_text);
		$notify->set_timeout(4000);
		$notify->show;
	}
	
	
}
sub CalculateButton
{
	#generate random with existing IDs
	return unless @$IDs;

	if ($::Options{OPT.'show_notifications'} == 1)
	{
		$notify_text = 'Calculating random album';
		$notify->update($notify_header,$notify_text);
		$notify->set_timeout(4000);
		$notify->show;
	}
	
	$startup = 0;
	$autocalculate = 0;
	
	CalculateDB;
	ExportStats;
	CalculateAlbum;	
}
sub ChooseSourceAndCalculate
{	

	$IDs=$_[0]{IDs} || $_[0]{filter}->filter;
	return unless @$IDs;

	if ($::Options{OPT.'show_notifications'} == 1)
	{
		$notify_text = 'Calculating DB & random album';
		$notify->update($notify_header,$notify_text);
		$notify->set_timeout(4000);
		$notify->show;
	}
	$startup = 0;
	$autocalculate = 0;
	CalculateDB;
	ExportStats;
	CalculateAlbum;
}

sub Changed
{

  if ($update_on_change == 1) { $update_on_change = 0; CalculateUpdate; }

  if ($::Options{OPT.'infinite'} == 1)
  {	
  	my ($pla,$pld,$plalb) = Songs::Get($::PlayingID,qw/album_artist year album/);

  	my $aa = $pla.$pld.$plalb;
  	
  	if (!($aa eq $current_artistalbum))
  	{
  		#switched manually from album, let's cut off infinite mode (and => updates)
  		@needsupdate = ();
		#$::Options{OPT.'infinite'} = 0;
  		if (($::Options{OPT.'show_notifications'} == 1) && ($current_last_ID != -1))
		{
			$notify_text = 'Infinite Mode cut off (manual change noted)';
			$notify->update($notify_header,$notify_text);
			$notify->set_timeout(4000);
			$notify->show;
		}
  		$current_last_ID = -1;
  	}

    #let's grab all the playing songs if 'infinite mode'
    push(@needsupdate,$::PlayingID);
  }

  if ($current_last_ID == $::PlayingID)
  {
  	if ($::Options{OPT.'infinite'} == 1)
  	{
	  	$autocalculate = 1;
  		if (scalar@needsupdate > 0) { $update_on_change = 1; $update_item = $current_item;}
  		
  		if ($::Options{OPT.'show_notifications'} == 1)
		{
  			$notify_text = 'Calculating next album';
			$notify->update($notify_header,$notify_text);
			$notify->set_timeout(4000);
			$notify->show;
		}
  		
  		ExportStats;
  		CalculateAlbum;
  	}
  	elsif ($::Options{OPT.'return_playmode_after_album'} == 1)
  	{
		::ToggleSort if !($::RandomMode);
  		$current_last_ID = -1;
  	}
  } 	

}

1 #the file must return true
