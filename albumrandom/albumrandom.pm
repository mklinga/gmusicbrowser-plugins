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
title	AlbumRandom plugin (v.2)
desc	Albumrandom plays albums according to set weighted random.
=cut

# the plugin package must be named GMB::Plugin::PID (replace PID), and must have these sub :
# Start	: called when the plugin is activated
# Stop	: called when the plugin is de-activated
# prefbox : returns a Gtk2::Widget used to describe the plugin and set its options

#TODO

package GMB::Plugin::ALBUMRANDOM;
use strict;
use warnings;

use constant
{	OPT	=> 'PLUGIN_ALBUMRANDOM_',
};

use Gtk2::Notify -init, ::PROGRAM_NAME;

::SetDefaultOptions(OPT, writestats => 1, infinite => 1, shownotifications => 0, recalculate_time => 12, recalculate => 1
, requireallinfilter => 0, topalbumsonly => 1, topalbumamount => 50, multipleamount => 3, rememberplaymode => 1);

my $ON=0;

my %arb2=
(	class	=> 'Layout::Button',
	state	=> sub {$ON==1? 'albumrandom_on' : 'albumrandom_off'},
	stock	=> {albumrandom_on => 'plugin-albumrandom-on', albumrandom_off => 'plugin-albumrandom' },
	tip	=> " Albumrandom v.2 \n LClick - generate new random album \n MClick - Re-update Database \n RClick - Toggle Infinite Mode ON/OFF",	
	click1	=> \&CalculateButton,
	click2	=> \&RecalculateButton,
	click3 => \&ToggleInfinite,
	autoadd_type	=> 'button main',
	event	=> 'AlbumrandomOn',
);

use base 'Gtk2::Box';
use base 'Gtk2::Dialog';
use utf8;


my $Logfile = $::HomeDir.'albumrandom.log';
my $Log=Gtk2::ListStore->new('Glib::String');

my $notify=undef;
my ($Daemon_name,$can_actions,$can_body);

my $handle;
my $IDs = ();
my $logContent = '';
my $lastSong = -1;
my $originalMode=-1;

my $selected=-1;
my $oldSelected = -1;
my $oldID = -1;
my $lastDBUpdate;

sub Start
{
	my $self=shift;

	Log("*** Initializing Albumrandom ***");

	Layout::RegisterWidget(Albumrandom=>\%arb2);
	
	$handle={};	#the handle to the Watch function must be a hash ref, if it is a Gtk2::Widget, UnWatch will be called when the widget is destroyed
	::Watch($handle, PlayingSong	=> \&Changed, Save	=> \&WriteStats);
}
sub Stop
{
	$ON=0;
	::HasChanged('AlbumrandomOn');
	$notify=undef;
	Layout::RegisterWidget('Albumrandom');
	::UnWatch($handle,'PlayingSong');
	::UnWatch($handle,'Save');
}

sub prefbox
{
	my $vbox= Gtk2::VBox->new(::FALSE, 2);

	my $check=::NewPrefCheckButton(OPT."writestats",'Write statistics',horizontal=>1);
	my $check2=::NewPrefCheckButton(OPT."infinite",'Infinite mode',horizontal=>1);
	my $check3=::NewPrefCheckButton(OPT."shownotifications",'Show notifications',horizontal=>1);
	my $check4=::NewPrefCheckButton(OPT."requireallinfilter",'Require all tracks of album in filter',horizontal=>1);	
	my $check5=::NewPrefCheckButton(OPT."rememberplaymode",'Remember & restore original playmode after Albumrandom finishes',horizontal=>1);
	
	my $button=Gtk2::Button->new();
	$button->signal_connect(clicked => \&GenerateRandomAlbum);
	$button->set_label("Generate (and enqueue) random album now");

	my $button2=Gtk2::Button->new();
	$button2->signal_connect(clicked => \&GenerateMultipleAlbums);
	$button2->set_label("Generate multiple albums now");
	
	my $time_spin=::NewPrefSpinButton(OPT."recalculate_time", 1,168, step=>1, page=>4, wrap=>0);
	my $time_entry=::Hpack($time_spin,Gtk2::Label->new(' hours'));
	my $checkn=::NewPrefCheckButton(OPT."recalculate",'Re-calculate DB after ', widget=>$time_entry,horizontal=>1);
	
	my $top_nb=::NewPrefSpinButton(OPT."topalbumamount", 2,5000, step=>1,text1=>_" ", text2=>_" albums");
	my $topcheck=::NewPrefCheckButton(OPT."topalbumsonly",'Select only from top ', , widget=>$top_nb, horizontal=>1);
	
	my @list2 = ::GetListOfSavedLists();
	my $listcombo= ::NewPrefCombo( OPT.'multiplelist', \@list2);
	
	my $album_spin=::NewPrefSpinButton(OPT."multipleamount", 1,1000, step=>1, page=>4, wrap=>0);
	my $albumlabel1=Gtk2::Label->new('Multiple random: Generate ');
	my $albumlabel2=Gtk2::Label->new(' albums to ');
	
	my $fi = ::Vpack([$check,$check2],[$check3,$check4],$check5,$topcheck,$checkn,[$albumlabel1,$album_spin,$albumlabel2,$listcombo],[$button,$button2]);
	$fi->add(::LogView($Log));
	
	return $fi;

}
sub Changed
{
	return Log("Tried to change with same ID twice!") if ($oldID == $::SongID);
	
	#this has to be here, because it might get called even after plugin has shut down (e.g. when infinite mode is OFF, and album is played through)
	if ($oldSelected != -1)
	{
		UpdateAlbumFromID($oldSelected);
		$oldSelected = -1;
		Log("Reset old selection");
	}

	return if ($selected == -1);#no business here, if haven't selected an album	

	my $al = AA::GetIDs('album',$IDs->[0][$selected]);
	my $isInAlbum=0;
	foreach my $track (@$al) { if ($::SongID == $track) {$isInAlbum = 1;}}

	if ($isInAlbum == 0) 
	{ 
		$ON = 0; 
		::HasChanged('AlbumrandomOn'); 
		Log("*** Manual change noted ***");
		Log("Trying to update last good album...");
		if ($selected != -1){ UpdateAlbumFromID($selected);}
		elsif ($oldSelected != -1){ UpdateAlbumFromID($oldSelected);}
		else { Log("Couldn't update - no suitable albumID left.");}
		$selected = -1; #set selected to -1, since we're not playing anything anymore
		Log("Trying to revert original playmode...");
		RestorePlaymode();
		return;
	}
	
	if ($::SongID == $lastSong)
	{
		Log("Last song playing, setting oldSelected");
		$oldSelected = $selected;
		
		if ($::Options{OPT.'infinite'} == 1){ Log("Infinite Mode: Generating next album"); GenerateRandomAlbum(); }
		else
		{
			#no more albums to play
			$ON = 0;
			::HasChanged('AlbumrandomOn');
			$selected = -1;
			Log("No infinite mode - just checking about restoring playmode");
			RestorePlaymode();
			Log("*** No more albums to play - shutting plugin off ***");
			return;
		}
	}
	
	WriteStats();
}
sub Notify
{
	my $notify_text = $_[0] if $_[0];

	return if ($ON == 0);
	return if ($::Options{OPT.'shownotifications'} == 0); 
	return if (not defined $notify_text);
	
	if (not defined $notify)
	{
		Log("Initializing notify");
		$notify=Gtk2::Notify->new('empty','empty');
		my ($name, $vendor, $version, $spec_version)= Gtk2::Notify->get_server_info;
		$Daemon_name= "$name $version ($vendor)";
		my @caps = Gtk2::Notify->get_server_caps;
		$can_body=	grep $_ eq 'body',	@caps;
		$can_actions=	grep $_ eq 'actions',	@caps;
	}

	my $notify_header = "Albumrandom";
	$notify->update($notify_header,$notify_text);
	$notify->set_timeout(4000);
	$notify->show;
	return 1;
}

sub Log
{
	my $text=$_[0];
	
	$Log->set( $Log->prepend,0, localtime().'  '.$text );
	if (my $iter=$Log->iter_nth_child(undef,5000)) { $Log->remove($iter); }
	
	$logContent .= localtime().' '.$text."\n";
}

sub RestorePlaymode
{
	if ($::Options{OPT.'rememberplaymode'} == 1)
	{
		if (($originalMode == 0) and ($::RandomMode)) { Log("Setting playmode straight"); ::ToggleSort;}
		elsif (($originalMode == 1) and (!($::RandomMode))) { Log("Setting playmode to Random"); ::ToggleSort;}
		elsif (($originalMode == 2) and ($::RandomMode)) { Log("Setting playmode straight & shuffle"); ::ToggleSort; ::Shuffle;}
		elsif (($originalMode == 2) and (!($::RandomMode))) { Log("Shufflin' up the playlist"); ::Shuffle;}
		elsif ($originalMode == -1) { Log("Couldn't find original playmode"); }
		else {Log("Original playmode is already set");}
	}
	else {return 0;}
	
	return 1;
}

sub CalculateButton
{
	GenerateRandomAlbum();
}

sub RecalculateButton
{
	if (CalculateDB(1) != 0) {Notify("Forced DB-update successfull");}
	WriteStats();
}

sub ToggleInfinite
{
	if ($::Options{OPT.'infinite'} == 0) { $::Options{OPT.'infinite'} = 1; Notify("Infinite mode is ON"); }
	else { $::Options{OPT.'infinite'} = 0; Notify("Infinite mode is OFF"); }
	
}

sub GenerateMultipleAlbums
{
	$ON = 1;
	::HasChanged('AlbumrandomOn');
	if (CalculateDB() == 0) { Log("CalculateDB FAILED"); return;};
	
	my $res = CalculateAlbum($::Options{OPT.'multipleamount'});
	if ($res == 0) { Log("CalculateAlbum FAILED"); return;}
	elsif ($res != 4) { Log("CalculateAlbum returned ".$res." for multiple generation. I wonder why."); return;}

	Log("Successfully generated multiple albums");
	
	WriteStats();
	return 1;
}
sub GenerateRandomAlbum
{
	$ON = 1;
	::HasChanged('AlbumrandomOn');
	if (CalculateDB() == 0) { Log("CalculateDB FAILED"); return;};
	if (CalculateAlbum() == 0) { Log("CalculateAlbum FAILED"); return;};

	Log("Successfully generated new album");
	
	WriteStats();
	return 1;	
}

sub CalculateDB
{
	my $force = $_[0] if ($_[0]);
	
	return if ($ON == 0);
	if ((not defined $force) and (defined $IDs->[0]))
	{
		#don't calculate again, unless it's about time
		if ($::Options{OPT.'recalculate'} == 1)
		{
			my $updatetime = $lastDBUpdate + ($::Options{OPT.'recalculate_time'}*3600);
			if (time > $updatetime) { Log("Re-calculating DB (timed update)"); }
			else {Log("DB already calculated - will update after ".int(0.5+(($updatetime-time)/60))." minutes (timed update)");return 3;}
		}
		else {Log("DB already calculated - returning");return 2;}
	}

	if (defined $force) {Log("Starting Database calculation (FORCED)");}
	else {Log("Starting Database calculation");}
	Notify('Calculating DB');

	my $al=AA::GetAAList('album');
	Log("Found ".scalar@$al." albums");

	my $totalPropability=0;
	my @albumPropabilities = ();
	
	if ($::RandomMode)
	{
		Log("Found RandomMode - setting originalMode to \'1\'");
		$originalMode = 1;

		#calculate random values according to selected mode
		foreach my $key (@$al)
		{
			my $list=AA::GetIDs('album',$key);
			my $curPropability=0;
			
			foreach my $track (@$list) { $curPropability += $::RandomMode->CalcScore($track); }
			
			$curPropability /= scalar@$list;
			push @albumPropabilities,$curPropability;
			
			Log("Set propability ".sprintf("%.3f",$curPropability)." for ".Songs::Get(@$list->[0],'album'));
			
			$totalPropability += $curPropability;
		}
	}
	else #straight playmode -> treat every album as equal
	{
		Log("No RandomMode selected - setting originalMode to \'0\'");
		if ($::Options{Sort}=~m/shuffle/) {$originalMode = 2;}
		else {$originalMode = 0;}
		
		foreach my $a (@$al) {push @albumPropabilities,1;}
		$totalPropability = scalar@$al;
	}

	Log("Total propability seems to be ".sprintf("%.3f (avg ~ %.3f)",$totalPropability,($totalPropability/scalar@$al)));
	@$IDs = (\@$al,\@albumPropabilities);

	$lastDBUpdate = time;
	Log("DB succesfully updated");
	
	return 1;
}

sub CalculateAlbum
{
	my $wanted = $_[0] if ($_[0]);
	
	if (not defined $wanted) { $wanted = 1; }
	
	Log("Calculating for ".$wanted." random album");
	
	return if ($ON == 0);
	return Log("No IDs") unless @$IDs;
	
	Log("Calculating Album");
	
	my $previous = $selected;
	$selected=-1;
	my $albumAmount = -1;
	my $albumkeys = @$IDs->[0];
	my $propabilities = @$IDs->[1];
	my @okAlbums = ();
	
	my $songlist = $::ListPlay; 
	
	my @indices = 1..$#$albumkeys;
	
	#sort indices decreasing by propability if selected 'topalbums'
	if ($::Options{OPT.'topalbumsonly'} == 1)
	{
		$albumAmount = $::Options{OPT.'topalbumamount'};
		@indices = sort { $propabilities->[$b] <=> $propabilities->[$a] } 0..(scalar@$propabilities-1);
		Log("Calculated top albums (rearranged index table)");
		Log("Set albumlimit to ".$albumAmount." top albums");
	}

	#we find out which albums are 'ok' to choose (due to filtering/playlist)
	#don't put previously selected album to okTable, to prevent from playing same album twice in a row
	my $current = -1;
	my $totalPropability = 0;
	foreach my $alb (@$albumkeys)
	{
		$current++;
		
		if ($indices[$current] != $previous)
		{
			my $aID = AA::GetIDs('album', $albumkeys->[$indices[$current]]);

			if ($songlist == $::Library)
			{
					push @okAlbums, $indices[$current];
					$totalPropability += $propabilities->[$indices[$current]];
			}
			else
			{
				my $inFilter = $songlist->AreIn($aID);
				
				if ((($::Options{OPT.'requireallinfilter'} == 1) and (scalar@$inFilter == scalar@$aID)) or (($::Options{OPT.'requireallinfilter'} == 0) and (scalar@$inFilter > 0))) 
				{
					push @okAlbums, $indices[$current];
					$totalPropability += $propabilities->[$indices[$current]];
				}
			}

			if (($::Options{OPT.'topalbumsonly'} == 1) and ($current<10))
			{
				if ($current == 0) { Log("Top albums");}
				Log(sprintf("%d. %s (%.3f)",($current+1),Songs::Get($aID->[0],'album'),$propabilities->[$indices[$current]]));
			} 	

		}
		if (scalar@okAlbums == $albumAmount) {Log("Found enough album for top list"); last; }
	}
	
	if (scalar@okAlbums == 0)  { Log("Error! No okAlbums in CalculateAlbum"); return 0;}
	if ($totalPropability == 0) { Log("Error! \$totalPropability == 0 in CalculateAlbum"); return 0;}
	
	Log("Generating from ".scalar@okAlbums." albums");
	Log(sprintf("Average propability for an album is ~ %.3f",($totalPropability/scalar@okAlbums)));
	
	
	if (($wanted > 1) and (scalar@okAlbums <= $wanted)) 
	{ 
			Log("All albums selected for multiple random!"); 
			MultipleAlbums(\@okAlbums); 
			return 4;
	}

	#generate random number and scroll through okTable, until $wanted is met
	my @foundAlbums = ();
	my $counter = 0;
	while ((scalar@foundAlbums < $wanted) and ($counter < 32768))
	{
		$counter++;
		my $r=rand($totalPropability);
		my $tp=0;
		my $current=-1;
		Log("Random number: ".$r." (of ".$totalPropability.")");
		
		foreach my $okA (@okAlbums)
		{
			$current++;
			$tp += $propabilities->[$okA];
			if ($tp > $r)
			{
				push @foundAlbums, $okA;
				Log (scalar@foundAlbums.": Found random album!");
				last; 
			}
		}
		$totalPropability -= $propabilities->[$current];
		splice @okAlbums, $current, 1;
	}

	#if we were generating multiple albums, send them forward and exit gracefully
	if ($wanted > 1) { Log("Sending ".scalar@foundAlbums." random albums to MultipleAlbum()"); MultipleAlbums(\@foundAlbums); return 4;}

	#otherwise our only selected album should be in foundAlbums[0]
	$selected = $foundAlbums[0];
	
	my $al = AA::GetIDs('album',$IDs->[0][$selected]);
	Log("Selected album: ".Songs::Get(@$al->[0],'album'));
	Log("propability for selected: ".$IDs->[1][$selected]);
	
	Songs::SortList($al,'disc track file');
	my $firstSong = @$al->[0];
	$lastSong = @$al->[scalar@$al-1]; 
	
	Log("Found first song of the album: ".Songs::Get($firstSong,'title'));
	Log("Found last song of the album: ".Songs::Get($lastSong,'title'));

	if ($::RandomMode || $::Options{Sort}=~m/shuffle/)
	{
		Log('Changing playmode to \'straight\'');
		::Select('sort' => 'album_artist year album disc track');
	}
	::Enqueue($firstSong);
	
	Log("Random Album generation successfull!");
	return 1;
}

sub UpdateAlbumFromID
{
	my $albumID = $_[0];

	Log("Starting Album Update");
	
	my $rmtoggled = 0;

	if (($originalMode == 1) and (!($::RandomMode)))
	{
		Log("Switching to RandomMode for calculation");
		::ToggleSort;
		$rmtoggled = 1;
	}
	
	my $al = AA::GetIDs('album',$IDs->[0][$albumID]);
	Log("Old propability for ".Songs::Get(@$al->[0],'album').": ".$IDs->[1][$albumID]);
	
	my $curPropability = 0; 
	if ($::RandomMode) {
		foreach my $track (@$al) { $curPropability += $::RandomMode->CalcScore($track);}
		$curPropability /= scalar@$al;
		Log("Updating with Random Mode");
	}
	else {$curPropability = 1; Log("Updating with Straight Mode"); }
	
	$IDs->[1][$albumID] = $curPropability;
		
	Log("Updated new propability for ".Songs::Get(@$al->[0],'album').": ".sprintf("%.3f",$curPropability));
	
	if ($rmtoggled == 1) {Log("Reverting play mode after update"); ::ToggleSort;}
	
	return 1;
}

sub MultipleAlbums()
{
	my $albumlistref = $_[0];
	Log("MultipleAlbums() here! I have ".scalar@$albumlistref." albums and I'm going to put them to static list.");
	
	my @trackIDs = ();
	foreach my $alr (@$albumlistref)
	{
		my $al = AA::GetIDs('album',$IDs->[0][$alr]);
		foreach my $trc (@$al) { push @trackIDs,$trc;}
	}
	
	if ($::Options{OPT.'multiplelist'} ne ''){::SaveList($::Options{OPT.'multiplelist'},\@trackIDs);}
	else {::SaveList('albumrandom',\@trackIDs);}
}

sub WriteStats()
{
	return 'no logfile' unless defined $Logfile;
	return 'statwriting not enabled' if ($::Options{OPT.'writestats'} == 0);

	open my $fh,'>',$Logfile or warn "Error opening '$Logfile' for writing : $!\n";
	print $fh $logContent   or warn "Error writing to '$Logfile' : $!\n";
	close $fh;
	
	print $logContent;
	
	Log("*** Stats have been written to ".$Logfile." ***");
}

1 #the file must return true
