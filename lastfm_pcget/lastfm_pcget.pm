# Gmusicbrowser: Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
# Lastfm_pcGet: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
#
# This file is a plugin to Gmusicbrowser.
# It is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.


=gmbplugin LASTFM_PCGET
name	lastfm_pcGet
title	playcount fetcher (v0.2)
desc	Downloads playcount for currently playing song
=cut

# TODO
# - love tracks, example of POST:
# 
#         use HTTP::Request::Common qw(POST);
#         use LWP::UserAgent;
#         $ua = LWP::UserAgent->new;
#
#         my $req = POST 'http://www.perl.com/cgi-bin/BugGlimpse',
#                      [ search => 'www', errors => 0 ];
#
#         print $ua->request($req)->as_string;




package GMB::Plugin::LASTFM_PCGET;
use strict;
use warnings;
use constant
{	CLIENTID => 'gmusicbrowser / last.fm_pcget', VERSION => '0.2',
	OPT => 'PLUGIN_LASTFM_PCGET_',#used to identify the plugin's options
	APIKEY => '58b7cf77be819f5473bffee8d781d9c0',
};

::SetDefaultOptions(OPT, pcvalues => 'always', multiple => 'split_evenly',checkcorrections => 1, titlechange => 'change_all', artistchange => 'change_all');

use utf8;
use Digest::MD5 'md5_hex';
require $::HTTP_module;

my $self=bless {},__PACKAGE__;
my $Log=Gtk2::ListStore->new('Glib::String');
my $waiting;
my $oldID = -1;
my $Datafile = $::HomeDir.'lastfm_corrections';
my $Banfile = $::HomeDir.'lastfm_corrections.banned';
my @corrections;
my @checks; my @banned;
my $s2; 
my $LOVED=0; my $token;


my %button=
(	class	=> 'Layout::Button',
	state	=> sub {($LOVED==1)? 'loved' : 'not_loved'},
	stock	=> {loved => 'lastfm_heart', not_loved => 'lastfm_heart_empty' },
	tip	=> "Love this track",	
	click1	=> \&ToggleLoved,
	autoadd_type	=> 'button main',
	event	=> 'lastfm_LovedStatus',
);
 

sub Start
{
	Layout::RegisterWidget(lastfmLoveButton=>\%button);
	::Watch($self,PlayingSong=> \&SongChanged);
	loadCorrections();
	loadBanned();
}
sub Stop
{
	$waiting->abort if ($waiting);
	::UnWatch_all($self);
	Layout::RegisterWidget('lastfmLoveButton');
}

sub prefbox
{
	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $vbox2=Gtk2::VBox->new(::FALSE, 2);
	my $sg1=Gtk2::SizeGroup->new('horizontal');
	my $sg2=Gtk2::SizeGroup->new('horizontal');
	my $entry1=::NewPrefEntry(OPT.'USER',_"Username: ", sizeg1 => $sg1,sizeg2=>$sg2);
	
	my $listcombo= ::NewPrefCombo( OPT.'pcvalues', { always => 'Always set last.fm value', biggest => 'Set bigger amount', smallest => 'Set smaller amount',});
	my $l=Gtk2::Label->new('How to deal with different playcount values: ');

	my $listcombo2= ::NewPrefCombo( OPT.'multiple', { playing => 'Set only playing tracks playcount', split_evenly => 'Split playcount evenly', separate => 'Set every tracks playcount separately', as_one => 'Handle different songs as one',});
	my $l2=Gtk2::Label->new('In case of multiple tracks with same artist and title: ');

	my $button2=Gtk2::Button->new();
	$button2->signal_connect(clicked => \&Correct);
	$button2->set_label("Show Corrections");

	my $check=::NewPrefCheckButton(OPT."checkcorrections",'Check for corrections',horizontal=>1);
	my $cl=Gtk2::Label->new();
	
	if (scalar@corrections == 1){$cl->set_label(" ".scalar@corrections." correction noted");}
	else {$cl->set_label(" ".scalar@corrections." corrections noted");}

	my $listcombo3= ::NewPrefCombo( OPT.'titlechange', { change_one => 'Change only the noted track', change_all => 'Change all songs with same artist/title',});
	my $l3=Gtk2::Label->new('When correcting track title: ');

	my $listcombo4= ::NewPrefCombo( OPT.'artistchange', {change_one => 'Change only for the noted track', change_all => 'Change all tracks from artist',});
	my $l4=Gtk2::Label->new('When correcting artist: ');
	

	my $frame1=Gtk2::Frame->new(_" Playcount fetching ");
	my $frame2=Gtk2::Frame->new(_" Track/Artist correction ");

	$vbox=::Vpack($entry1,[$l,$listcombo],[$l2,$listcombo2]);
	$vbox2=::Vpack($check,[$l3,$listcombo3,$l4,$listcombo4],[$button2,$cl]);

	$frame1->add($vbox);
	$frame2->add($vbox2);
	
	my $fi = ::Vpack( $frame2, $frame1);
	$fi->add(::LogView($Log));
	
	return $fi;
}

sub ToggleLoved
{
	if (not defined $::Options{OPT.$::Options{OPT.'USER'}.'sessionkey'})
	{
		my$dialog = Gtk2::MessageDialog->new (undef,
                                      'destroy-with-parent',
                                      'question', # message type
                                      'yes-no', # which set of buttons?
                                      "You need last.fm sessionkey for this action.\nDo you want to configure it now?");
		my $response = $dialog->run;		
		GetSessionKey() if ($response eq 'yes');
		$dialog->destroy;
	}
	else
	{
		SendLoveRequest();
	}
}

sub SendLoveRequest
{
	return unless ((defined $::Options{OPT.$::Options{OPT.'USER'}.'sessionkey'}) and (defined $::Options{OPT.'USER'}));
	
	my $sk = $::Options{OPT.$::Options{OPT.'USER'}.'sessionkey'};
	my $user = $::Options{OPT.'USER'};
	my ($artist,$title) = Songs::Get($::SongID,qw/artist title/);
#warn "Attempting to love ".$artist.' - '.$title.' with user: '.$user.', api_key: '.APIKEY.' and session key: '.$sk;	
	my $signature = md5_hex("api_key".APIKEY.'artist'.$artist.'methodtrack.lovesk'.$sk.'track'.$title.'bfe7a3fd2eacbd28336cc0dfc9b2dd4d');
#warn 'Signature made from '."api_key".APIKEY.'artist'.$artist.'methodtrack.lovesk'.$sk.'track'.$title;
#warn 'Signature ='.$signature;	
	my $post = 'method=track.love&track='.$title.'&artist='.$artist.'&api_key='.APIKEY.'&sk='.$sk.'&api_sig='.$signature;
	
	Send(\&HandleLoveRequest,'http://ws.audioscrobbler.com/2.0/',$post);	
}

sub HandleLoveRequest
{
	my @response = @_;
	my $allIsWell=0;
	foreach my $line (@response) {
		$allIsWell = 1 if ($line =~ m/lfm status=\"ok\"/);
	}
	
	 if ($allIsWell) {
	 	SetLoved(1);
	 	Log('Loved track '.Songs::Get($::SongID,'artist').' - '.Songs::Get($::SongID,'title').' successfully!');
	 }
	 else { Log('ERROR: Something went wrong when tried to love track.');}
	
	return $allIsWell;
}

sub GetSessionKey
{	
	my $user=$::Options{OPT.'USER'};
	return 0 unless defined $user && $user ne '';

	my $signature = md5_hex("api_key".APIKEY.'methodauth.gettoken'.'bfe7a3fd2eacbd28336cc0dfc9b2dd4d');
	Send(\&HandleLastfmToken,'http://ws.audioscrobbler.com/2.0/?method=auth.gettoken&api_key='.APIKEY);

}

sub HandleLastfmToken
{
	my @response = @_;
	foreach my $line (@response) {
		if ($line =~ m/<token>(.+)<\/token>/){ $token = $1; last;}
	}
	return 0 unless (defined $token);

	my $dialog = Gtk2::Dialog->new ('Confirmation', undef,[qw/modal destroy-with-parent/]);
	$dialog->set_position('center-always');
	$dialog->set_border_width(4);
	
    my $label = Gtk2::Label->new("This property needs to have permission to your last.fm data in order to work.\nPlease give your permission in last.fm internet page BEFORE pressing continue!\nYou can do this in following address:");
    my $label2 = Gtk2::Label->new;
    $label2->set_markup('<span underline="single" color="blue">'.::PangoEsc('http://www.last.fm/api/auth/?api_key='.APIKEY.'&token='.$token).'</span>'); 
    $label2->set_ellipsize('middle');
    $label2->set_max_width_chars(50);
    
    my $next = Gtk2::Button->new('I have accepted permission in last.fm, continue!');
    $next->set_sensitive(0);
    my $runbutton = Gtk2::Button->new('Open in browser');
    
    $runbutton->signal_connect(clicked => sub {
    	::main::openurl('http://www.last.fm/api/auth/?api_key='.APIKEY.'&token='.$token);
    	$next->set_sensitive(1);
    });

	$next->signal_connect(clicked => sub {
		$dialog->destroy;
		
		#then final authing
		my $signature = md5_hex("api_key".APIKEY.'methodauth.getsessiontoken'.$token.'bfe7a3fd2eacbd28336cc0dfc9b2dd4d');
		Send(\&HandleLastfmSessionKey,'http://ws.audioscrobbler.com/2.0/?method=auth.getsession&api_key='.APIKEY.'&token='.$token.'&api_sig='.$signature);		
	});
    
    my $dform = ::Vpack($label,$label2);
    $dform->add(::Hpack('-',$next,'-',$runbutton));
	$dialog->get_content_area ()->add ($dform);
	$dialog->set_default_response(1);
	$dialog->show_all;

	$dialog->run;
	$dialog->destroy();
}

sub HandleLastfmSessionKey
{
	my @resp = @_;
	my $key;
	
	for my $line (@resp) 
	{
		if ($line =~ m/<key>(.+)<\/key>/){ $key = $1; last;}
	}
	
	if (defined $key){
		$::Options{OPT.$::Options{OPT.'USER'}.'sessionkey'} = $key;
		Log('Successfully acquired last.fm session key for user: '.$::Options{OPT.'USER'}.'!');		
	}
	else { Log('ERROR! No sessionkey found! Did you give permission for it?'); return 0;}

	return 1;
}

sub Send
{	my ($response_cb,$url,$post)=@_;
	my $cb=sub
	{	my @response=(defined $_[0])? split "\012",$_[0] : ();
		&$response_cb(@response);
	};
	$waiting=Simple_http::get_with_cb(cb => $cb,url => $url,post => $post);
}


sub SongChanged
{
	return if ($oldID == $::SongID);
	
	$oldID = $::SongID;
	Sync();
}


sub Log
{	my $text=$_[0];
	$Log->set( $Log->prepend,0, localtime().'  '.$text );
	warn "$text\n" if $::debug;
	if (my $iter=$Log->iter_nth_child(undef,200)) { $Log->remove($iter); }
}

sub loadCorrections()
{
	open(my $fh, '<', $Datafile) or return;
	@corrections = <$fh>;
	close($fh);
}

sub saveCorrections()
{
		return 'no datafile' unless defined $Datafile;

		my $content = '';
		
		foreach my $a (@corrections) { if ($a =~ m/(.+)\t(.+)\t(.+)/) {$content .= $a;}}

		open my $fh,'>',$Datafile or warn "Error opening '$Datafile' for writing : $!\n";
		print $fh $content   or warn "Error writing to '$Datafile' : $!\n";
		close $fh;
}

sub checkCorrection()
{
	return if ($waiting);

	my $artist = Songs::Get($::SongID,'artist');
	my $title = Songs::Get($::SongID,'title');

	my $url = 'http://ws.audioscrobbler.com/2.0/?method=track.getcorrection&artist='.::url_escapeall($artist).'&track='.::url_escapeall($title).'&api_key=b25b959554ed76058ac220b7b2e0a026';

	my $correcttrack = '';
	my $correctartist = '';
	
	my $cb=sub
	{	
		$waiting=undef;
		my @r=(defined $_[0])? split "\012",$_[0] : ();
		foreach my $a (@r) 
		{
			#if there is no corrections, <name> won't exist
			#if there is, it's always track first, then artist
			
			if ( $a =~ m/<name>(.+)<\/name>/)
			{
				 if ($correcttrack eq '') { $correcttrack = $1; }
				 elsif ($correctartist eq '') { $correctartist = $1; }
			}
		}
		
		if ($correcttrack ne '') 
		{
			if (my $utf8=Encode::decode_utf8($correcttrack)) {$correcttrack=$utf8}
			if (my $utf8=Encode::decode_utf8($correctartist)) {$correctartist=$utf8}
			
			my $new_correction = Songs::Get($::SongID,'fullfilename')."\t".$correctartist."\t".$correcttrack."\n";
			my $is_banned = 0;

			#then we check if current file has been banned or if it's already on @corrections
			foreach my $bb (@banned) { if ($bb eq $new_correction) { $is_banned = 1; }} 
			foreach my $bb (@corrections) { if ($bb eq $new_correction) { $is_banned = 1; }} 

			if ($is_banned == 0)
			{
				push(@corrections,$new_correction); 
				saveCorrections();
			} 
		}
	};
	my $waiting=Simple_http::get_with_cb(cb => $cb,url => $url,post => '');
}

sub findSimilar
{
	my $initialfilter = $_[0];
	my $oldartist = lc $_[1];
	my $oldtitle = lc $_[2];
	
	my @final = ();
	
	foreach my $a (@$initialfilter) 
	{
		my $artist = lc Songs::Get($a,'artist');
		my $title = lc Songs::Get($a,'title');
		
		if ((($oldartist eq '') or ($oldartist eq $artist)) and (($oldtitle eq '') or ($oldtitle eq $title))) { push @final,$a;}
	}
	
	return \@final;
}

sub GetPcValueSetting
{
	my ($newvalue,$oldvalue) = shift;
	
	$oldvalue = 0 unless (defined $oldvalue);
	if ($::Options{OPT.'pcvalues'} eq 'always') { return $newvalue; }
	elsif ($::Options{OPT.'pcvalues'} eq 'biggest') { return ($newvalue > $oldvalue)? $newvalue : $oldvalue;}
	elsif ($::Options{OPT.'pcvalues'} eq 'smallest') {return ($newvalue < $oldvalue)? $newvalue : $oldvalue; }
	
	Log('Error in GetPcValueSetting! Returning zero.');
	return 0; 
}

sub DistributeEvenly
{
	my ($value,$items,$songid) = @_;
	
	$songid = -1 unless (defined $songid);
	my $whole = int($value/scalar@$items);
	my $rest = $value%scalar@$items;
	my %valuehash;

	foreach (@$items)
	{
		if (($rest > 0) and ($_ != $songid)) { 
			$valuehash{$_} = $whole+1; 
			$rest--; 
		}
		else { 
			$valuehash{$_} = $whole;
		}
	}
	
	return \%valuehash;
}

sub SetValue
{
	my ($songid,$artist,$album,$title,$newvalue) = @_;
	
	my $multifilter=findSimilar(Filter->newadd(1,'title:s:'.$title, 'artist:s:'.$artist)->filter,$artist,$title);
	my %tochange;
	
	if ($::Options{OPT.'multiple'} eq 'playing') { 
		$tochange{$songid} = GetPcValueSetting($newvalue,Songs::Get($songid,'playcount'));
	}
	elsif ($::Options{OPT.'multiple'} eq 'split_evenly') {
		my $sum = 0;
		$sum += (Songs::Get($_,'playcount') || 0) for (@$multifilter);
		my $value = GetPcValueSetting($newvalue,$sum);
		%tochange = %{DistributeEvenly($value,$multifilter,$songid)};
	}
	elsif ($::Options{OPT.'multiple'} eq 'separate') {
		for (@$multifilter){
			$tochange{$_} = GetPcValueSetting($newvalue,Songs::Get($_,'playcount'));
		}
	}
	elsif ($::Options{OPT.'multiple'} eq 'as_one')
	{	
		my $avg = 0;
		$avg += (Songs::Get($_,'playcount') || 0) for (@$multifilter);
		$avg /= scalar@$multifilter;
		for (@$multifilter){
			$tochange{$_} = GetPcValueSetting($newvalue,$avg);
		}
	}
	
	my $num=0; my $pre='';
	for my $id (keys %tochange)
	{
		$num++;
		my $songoc = Songs::Get($id,'playcount');
		my ($art,$alb,$tit) = Songs::Get($id,qw/artist album title/);
		$pre = '['.($num).'/'.(scalar (keys %tochange)).'] ';

		if ((not defined $songoc) or ($tochange{$id} != $songoc))
		{
			Songs::Set($id,'playcount' => $tochange{$id});
			Log($pre."Set playcount to ".$tochange{$id}." for ".$art." - ".$alb." - ".$tit);
		}
		else { Log($pre."Nothing to change (playcount ".$tochange{$id}.") for ".$art." - ".$alb." - ".$tit) }
	}
	
	return 1;
}

sub SetLoved
{
	my $loved = shift;
	$LOVED=$loved;
	::HasChanged('lastfm_LovedStatus');
	return 1;
}
sub Sync()
{
	return if ($waiting);

	my $user = $::Options{OPT.'USER'};
	my $love = 0; #by default we show no love

	if ($user eq '') { return;}

	my $artist = Songs::Get($::SongID,'artist');
	my $album = Songs::Get($::SongID,'album');
	my $title = Songs::Get($::SongID,'title');

	my $url = 'http://ws.audioscrobbler.com/2.0/?method=track.getinfo&username='.$user.'&api_key='.APIKEY.'&artist='.::url_escapeall($artist).'&track='.::url_escapeall($title);
	
	my $cb=sub
	{	
		$waiting=undef;
		my @r=(defined $_[0])? split "\012",$_[0] : ();
		my $foundpc=0;
		foreach my $a (@r) 
		{
			if ( $a =~ m/<userplaycount>(\d+)<\/userplaycount>/){
				SetValue($::SongID,$artist,$album,$title,$1);
				$foundpc=1;
			}
		
			if ( $a =~ m/<userloved>(\d+)<\/userloved>/)	{
				$love = $1;
			}
		}
		
		if (!$foundpc) { Log('No previous playcount for '.$artist.' - '.$title);}
		SetLoved($love);
		
		if ($::Options{OPT.'checkcorrections'} == 1) {checkCorrection();}
	};
	my $waiting=Simple_http::get_with_cb(cb => $cb,url => $url,post => '');
}
sub Correct
{
	$s2 = Gtk2::Dialog->new(_"last.fm suggestions",undef,'destroy-with-parent');
	@checks = ();
	
	$s2->set_default_size(700, 400);
	$s2->set_position('center-always');
	$s2->set_border_width(6);

	# Contents: textentry, searchbutton, stopbutton and scrollwindow (for radiobuttons).
	$s2->{selall}= my $selall = ::NewIconButton('gtk-select-all', _"Select all");
	$s2->{selnone}	= my $selnone	  = ::NewIconButton('gtk-clear', _"Select none");
	$s2->{remsel}= my $remsel = ::NewIconButton('gtk-delete', _"Hide selected");
	$s2->{corsel}	= my $corsel	  = ::NewIconButton('gtk-save', _"Correct selected");
	$s2->{close}= my $close = ::NewIconButton('gtk-close', _"Close");
	$s2->{label1} = my $label1 = Gtk2::Label->new('These are last.fm\'s suggestions for corrections');
	$s2->{vbox}	= my $vbox = Gtk2::VBox->new(0,0);
	
	my $scrwin = Gtk2::ScrolledWindow->new();
	$scrwin->set_policy('automatic', 'automatic');
	$scrwin->add_with_viewport($vbox);
	$s2->get_content_area()->add( ::Vpack($label1,'_', $scrwin,[$selall, $selnone, $remsel, $corsel,$close]) );

	foreach my $a (@corrections)
	{
		if ($a =~ m/(.+)\t(.+)\t(.+)/)
		{
			push(@checks, Gtk2::CheckButton->new(Songs::Get(Songs::FindID($1),'artist')." - ".Songs::Get(Songs::FindID($1),'title')." -> ".$2." - ".$3));
		}
	}
	$s2->{vbox}->pack_start($_,0,0,0) foreach @checks;

	# Handle the relevant events (signals).
	#
	$close ->signal_connect(clicked => sub {$s2->destroy();});

	$remsel ->signal_connect(clicked => sub { confirm_action(1);});
	$corsel ->signal_connect(clicked => sub { confirm_action(2);});
	
	$s2->signal_connect(response => sub {$s2->destroy();});
	$s2->signal_connect(destroy => \&saveBanned);
	$selall->signal_connect(clicked  => sub {
		foreach my $c (@checks) { $c->set_active(1);}
	});
	$selnone->signal_connect(clicked  => sub {
		foreach my $c (@checks) { $c->set_active(0);}
	});

	$s2->show_all();
}

sub loadBanned()
{
	open(my $fh, '<', $Banfile) or return;
	@banned = <$fh>;
	close($fh);
}
sub saveBanned
{
	#write banned files to 'lastfm_corrections.banned' so they don't appear ever again
	return 'no datafile' unless defined $Banfile;

	my $content = '';
	
	return if (scalar@banned == 0);
	
	foreach my $a (@banned) { $content .= $a;}

	open my $fh,'>',$Banfile or warn "Error opening '$Banfile' for writing : $!\n";
	print $fh $content   or warn "Error writing to '$Banfile' : $!\n";
	close $fh;
}

sub confirm_action()
{
	my $type = $_[0];
	my $dialog = Gtk2::Dialog->new ('Confirmation', undef,[qw/modal destroy-with-parent/],'gtk-ok'     => 'ok','gtk-cancel' => 'cancel');
	$dialog->set_position('center-always');
	$dialog->set_border_width(4);

	$dialog->signal_connect(response => sub {$_[0]->destroy;
		if ($_[1] eq 'ok') 
		{ 
			if ($type == 1) {remove_selected();}
			elsif ($type == 2) {correctSelected(0);}
		}
	});
	
    my $label = Gtk2::Label->new();
    my $label2 = Gtk2::Label->new();
    if ($type == 1) 
    { 
    	$label->set_label('Selected corrections will be removed from list.');
    	$label2->set_label('To see them again you have to manually edit banned-file (see README).')
    }
    elsif ($type == 2) 
    { 
    	$label->set_label('Selected corrections will now be applied to filetags.');
    	$label2->set_label('You can\'t undo this operation.')
    	
    }
    $dialog->get_content_area ()->add ($label);
    $dialog->get_content_area ()->add ($label2);
    $dialog->show_all;
}

sub okDialog
{
	my $text1 = $_[0];
	my $text2 = $_[1];
	
	my $dialog = Gtk2::Dialog->new ('Success', undef,[qw/modal destroy-with-parent/],'gtk-ok'     => 'ok');
	$dialog->set_position('center-always');
	$dialog->set_border_width(4);

	$dialog->signal_connect(response => sub {$_[0]->destroy;});
	
    my $label = Gtk2::Label->new();
    my $label2 = Gtk2::Label->new();
   	$label->set_label($text1);
   	$label2->set_label($text2);

    $dialog->get_content_area ()->add ($label);
    $dialog->get_content_area ()->add ($label2);
    $dialog->show_all;
	
}
sub remove_selected
{
	my $ramount=0;
	for (my $c=(scalar@checks-1);$c >= 0; $c--)
	{
		if ($checks[$c]->get_active) 
		{ 
			push (@banned,$corrections[$c]); 
			$s2->{vbox}->remove($checks[$c]);
			splice @checks, $c, 1;				
			splice @corrections, $c, 1;
			$ramount++;
		}
	}
	saveBanned();
	saveCorrections();
	okDialog('Succesfully removed '.$ramount.' tracks from suggestions list','Succesfully updated \'lastfm_corrections.banned\'');
}
sub correctSelected()
{
	my @correctIDs = ();
	my $tamount=0;
	my $camount=0;

	for (my $c=0; $c < scalar@checks; $c++)
	{
		if ($corrections[$c] =~ m/(.+)\t(.+)\t(.+)/)
		{
			push @correctIDs, Songs::FindID($1);
		}
	}


	for (my $c=(scalar@checks)-1; $c >= 0; $c--)
	{
		if ($corrections[$c] =~ m/(.+)\t(.+)\t(.+)/)
		{
			my $ID = Songs::FindID($1);
			
			my $oldartist =  Songs::Get(Songs::FindID($1),'artist');
			my $oldtitle =  Songs::Get(Songs::FindID($1),'title');
			
			my $newartist = $2;
			my $newtitle = $3;
			
			my $changetype;
			
			if ($newtitle ne $oldtitle) { $changetype = 1;}
			if ($newartist ne $oldartist) { $changetype = 2;}
			if (($newartist ne $oldartist) and ($newtitle ne $oldtitle)) { $changetype = 3;}
			
			my $trackfilter;
			my @changeTitle;
			my @changeArtist;
			
			if (($changetype == 1) or ($changetype == 3))
			{	
				$trackfilter = findSimilar(Filter->newadd(1,'title:s:'.$oldtitle, 'artist:s:'.$oldartist)->filter,$oldartist,$oldtitle); 
				if ($::Options{OPT.'titlechange'} eq 'change_all') { foreach my $a (@$trackfilter) { push @changeTitle,$a;} }
			}
			
			if (($changetype == 2) or ($changetype == 3))
			{
				$trackfilter = findSimilar(Filter->newadd(1,'artist:s:'.$oldartist)->filter,$oldartist,''); 
				if ($::Options{OPT.'artistchange'} eq 'change_all') { foreach my $a (@$trackfilter) { push @changeArtist,$a;} }
			}

			#don't fix something that is already in the @corrections!			
			foreach my $ch (@correctIDs)
			{
				for (my $ca=0;$ca<scalar@changeArtist;$ca++) { if (($changeArtist[$ca] != $ID) and ($changeArtist[$ca] == $ch)) { splice @changeArtist, $ca, 1;}}
				for (my $ct=0;$ct<scalar@changeTitle;$ct++) { if (($changeTitle[$ct] != $ID) and ($changeTitle[$ct] == $ch)) { splice @changeTitle, $ct, 1;}}
			}
			
			if ($checks[$c]->get_active) 
			{ 
				$camount++;
				if ((scalar@changeTitle == 0) and (scalar@changeArtist == 0))
				{
					Songs::Set($ID, artist=> $newartist, title => $newtitle);
					Log('Corrected tag for '.$oldartist.' - '.$oldtitle.' -> '.$newartist.' - '.$newtitle);
					push @correctIDs, $ID;	
					$tamount++;
				}
				else
				{
					if (scalar@changeTitle > 0) 
					{
						Songs::Set(\@changeTitle, title => $newtitle);
						Log('Corrected title tag to \''.$newtitle.'\' for '.scalar@changeTitle.' tracks');
						foreach my $cT (@changeTitle) { push @correctIDs, $cT; }					
						$tamount += scalar@changeTitle;
					}
					if (scalar@changeArtist > 0) 
					{
						Songs::Set(\@changeArtist, artist => $newartist);
						Log('Corrected artist tag to \''.$newartist.'\' for '.scalar@changeArtist.' tracks');
						foreach my $cA (@changeArtist) { push @correctIDs, $cA; }					
						$tamount += scalar@changeArtist;
					}
				}
				$s2->{vbox}->remove($checks[$c]);
 				splice @checks, $c, 1;				
 				splice @corrections, $c, 1;
			}				
		}
	}
	saveCorrections();
	okDialog('Succesfully updated '.$camount.' tracks from suggestions list','Total of '.$tamount.' tracks were updated');
}

1;
