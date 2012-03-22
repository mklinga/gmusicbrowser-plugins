# Gmusicbrowser: Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
# History/Stats: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
#
# This file is a plugin to Gmusicbrowser.
# It is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

# TODO:
# - time-based (as in weekly/monthly etc.) stats 
# - don't update overview if nothing has changed
# - overview context-menus (tracks!), other list handling (merge pos in albumlabel / icon optional (hover?))
# - ignore 'by album wrandom sort calculating' for albums with many artists? tjeu: n&l ? 
#
# BUGS:
# - [ochosi:] pressing the sort-button in history/stats crashes gmb (cannot reproduce, dismiss?)
# - sorting the playedlength (for now)
#

=gmbplugin HISTORYSTATS
name	History/Stats
title	History/Stats - plugin
version 0.01
desc	Show playhistory and statistics in layout
=cut

package GMB::Plugin::HISTORYSTATS;

use strict;
use warnings;
use constant
{	OPT	=> 'PLUGIN_HISTORYSTATS_',
};

use utf8;
require $::HTTP_module;
use Gtk2::Gdk::Keysyms;
use base 'Gtk2::Box';
use base 'Gtk2::Dialog';

::SetDefaultOptions(OPT,RequirePlayConditions => 1, HistoryLimitMode => 'days', AmountOfHistoryItems => 3, 
	AmountOfStatItems => 50, UseHistoryFilter => 0, TotalPlayTime => 0, 
	TotalPlayTracks => 0, ShowArtistForAlbumsAndTracks => 1, HistoryTimeFormat => '%d.%m.%y %H:%M:%S',
	HistoryItemFormat => '%a - %l - %t',FilterOnDblClick => 0, LogHistoryToFile => 0, SetFilterOnLeftClick => 1,
	PerAlbumInsteadOfTrack => 0, ShowStatNumbers => 1, AddCurrentToStatList => 1, OverviewTopMode => 'playcount:sum',
	OverViewTopAmount => 5, CoverSize => 60, StatisticsTypeCombo => 'Artists',
	StatisticsSortCombo => 'Playcount (Average)', OverviewTop40Amount => 40, WeightedRandomEnabled => 1, WeightedRandomValueType => 1,
	StatImageArtist => 1, StatImageAlbum => 1, StatImageTitle => 1, OverviewTop40Item => 'Albums', LastfmStyleHistogram => 0,
	HistAlbumPlayedPerc => 50, HistAlbumPlayedMin => 40);

my %sites =
(
	statistics => ['',_"Statistics",_"Show statistics"],
	overview => ['',_"Overview",_"Overview of statistics"],
	history => ['',_"History",_"Show playhistory"]
);

my %StatTypes = (
 #album_artists => { label => 'Album Artists', field => 'album_artist'}, 
 artists => { label => 'Artists', field => 'artist'}, 
 albums => { label => 'Albums', field => 'album'}, 
 labels => { label => 'Labels', field => 'label'}, 
 genres => { label => 'Genres', field => 'genre'}, 
 year => { label => 'Years', field => 'year'}, 
 titles => { label => 'Tracks', field => 'title'} 
);

my %SortTypes = (
 playcount => { label => 'Playcount (Average)', typecode => 'playcount', suffix => ':average'}, 
 playcount_total => { label => 'Playcount (Total)', typecode => 'playcount', suffix => ':sum'}, 
 rating => { label => 'Rating', typecode => 'rating', suffix => ':average'},
 timecount_total => { label => 'Time played', typecode => 'playedlength', suffix => ':sum'},
 weighted_random => { label => 'Weighted random', typecode => 'weighted', suffix => ':average'} 
);

my %statupdatemodes = ( 
	songchange => 'On songchange', 
	albumchange => 'On albumchange', 
	initial => 'Only initially'
);

my %OverviewTopheads = (
	artist => {label => 'Top Artists', enabled => 1},
	album => {label => 'Top Albums', enabled => 0},
	title => {label => 'Top Tracks', enabled => 0},
	genre => {label => 'Top Genres', enabled => 0}
);

my $statswidget =
{	class		=> __PACKAGE__,
	tabicon		=> 'plugin-historystats',
	tabtitle	=> _"History/Stats",
	#schange		=> \&SongChanged,
	#group		=> 'Play',
	autoadd_type	=> 'context page text',
};

my $LogFile = $::HomeDir.'playhistory.log';
my %AdditionalData; #holds additional playcounts, key is 'pt' + (last playcount of track), value is array
my %HistoryHash = ( needupdate => 1);# last play of every track, key = 'pt'.Playtime
my %sourcehash;
my $lastID = -1; 
my %lastAdded = ( ID => -1, playtime => -1, albumID => -1);
my $lastPlaytime;
my %globalstats;

sub Start {
	Layout::RegisterWidget(HistoryStats => $statswidget);
	if (not defined $::Options{OPT.'StatisticsStartTime'}) {
		$::Options{OPT.'StatisticsStartTime'} = time;
	}
	$::Options{OPT.'StatWeightedRandomMode'} = ((sort keys %{$::Options{SavedWRandoms}})[0]) unless (defined $::Options{OPT.'StatWeightedRandomMode'});

	$globalstats{starttime} = $::Options{OPT.'StatisticsStartTime'}; 
	$globalstats{playtime} = $::Options{OPT.'TotalPlayTime'};
	$globalstats{playtrack} = $::Options{OPT.'TotalPlayTracks'};
	
	for (keys %OverviewTopheads) { 
		if (defined $::Options{OPT.'OVTH'.$_}) {$OverviewTopheads{$_}->{enabled} = $::Options{OPT.'OVTH'.$_};}
		else {$::Options{OPT.'OVTH'.$_} = $OverviewTopheads{$_}->{enabled};}
	}
	
	
}

sub Stop {
	Layout::RegisterWidget(HistoryStats => undef);
}

sub prefbox 
{
	
	my @frame=(Gtk2::Frame->new(" General options "),Gtk2::Frame->new(" History "),Gtk2::Frame->new(" Overview "),Gtk2::Frame->new(" Statistics "));
	
	#General
	my $gAmount1 = ::NewPrefSpinButton(OPT.'CoverSize',50,200, step=>10, page=>25, text =>_("Album cover size"));	

	# History
	my $hCheck1 = ::NewPrefCheckButton(OPT.'RequirePlayConditions','Add only songs that count as played', tip => 'You can set treshold for these conditions in Preferences->Misc', cb => sub{  $HistoryHash{needupdate} = 1;});
	my $hCheck2 = ::NewPrefCheckButton(OPT.'UseHistoryFilter','Show history only from selected filter', cb => sub{ $HistoryHash{needupdate} = 1;});
	my $hCheck3 = ::NewPrefCheckButton(OPT.'LogHistoryToFile','Log playhistory to file');
	my $hAmount = ::NewPrefSpinButton(OPT.'AmountOfHistoryItems',1,1000, step=>1, page=>10, text =>_("Limit history to "), cb => sub{  $HistoryHash{needupdate} = 1;});
	my @historylimits = ('items','days');
	my $hCombo = ::NewPrefCombo(OPT.'HistoryLimitMode',\@historylimits, cb => sub{ $HistoryHash{needupdate} = 1;});
	my $hEntry1 = ::NewPrefEntry(OPT.'HistoryTimeFormat','Format for time: ', tip => "Available fields are: \%d, \%m, \%y, \%h (12h), \%H (24h), \%M, \%S \%p (am/pm-indicator)");
	my $hEntry2 = ::NewPrefEntry(OPT.'HistoryItemFormat','Format for tracks: ', tip => "You can use all fields from gmusicbrowsers syntax (see http://gmusicbrowser.org/layout_doc.html)", cb => sub { $HistoryHash{needrecreate} = 1;});
	my $hAmount2 = ::NewPrefSpinButton(OPT.'HistAlbumPlayedPerc',1,240, step=>1, page=>10, text =>_("Count album as played after "));
	my $hAmount3 = ::NewPrefSpinButton(OPT.'HistAlbumPlayedMin',1,100, step=>1, page=>10, text =>_("% or "));
	my $hLabel1 = Gtk2::Label->new(' minutes');

	# Overview
	my $oAmount = ::NewPrefSpinButton(OPT.'OverViewTopAmount',1,20, step=>1, page=>2, text =>_("Items in toplists: "));
	my $oLabel1 = Gtk2::Label->new('Show toplists for (changing requires restart of plugin):');
	$oLabel1->set_alignment(0,0.5);
	my $oCheck1 = ::NewPrefCheckButton(OPT.'OVTHartist','Artists');
	my $oCheck2 = ::NewPrefCheckButton(OPT.'OVTHalbum','Albums');
	my $oCheck3 = ::NewPrefCheckButton(OPT.'OVTHtitle','Tracks');
	my $oCheck4 = ::NewPrefCheckButton(OPT.'OVTHgenre','Genres');
	my $oAmount2 = ::NewPrefSpinButton(OPT.'OverviewTop40Amount',3,100, step=>1, page=>5, text =>_("Items in main chart: "));
	my @omodes = ('weekly','monthly');
	my $oCombo = ::NewPrefCombo(OPT.'OverviewTop40Mode',\@omodes, text => 'Update main chart');
	my @omodes2 = ('Artists','Albums','Tracks');
	my $oCombo2 = ::NewPrefCombo(OPT.'OverviewTop40Item',\@omodes2, text => 'Show main chart for ');

	# Statistics
	my $sAmount = ::NewPrefSpinButton(OPT.'AmountOfStatItems',10,10000, step=>5, page=>50, text =>_("Limit amount of shown items to "));
	my $sCheck1 = ::NewPrefCheckButton(OPT.'ShowArtistForAlbumsAndTracks','Show artist for albums and tracks in list');
	my $sCheck2 = ::NewPrefCheckButton(OPT.'SetFilterOnLeftClick','Show items selected with left-click');
	my $sCheck3 = ::NewPrefCheckButton(OPT.'FilterOnDblClick','Set Filter when playing items with double-click', tip => 'This option doesn\'t apply to single tracks');
	my $sCheck4 = ::NewPrefCheckButton(OPT.'PerAlbumInsteadOfTrack','Calculate groupstats per album instead of per track');
	my $sCheck5 = ::NewPrefCheckButton(OPT.'ShowStatNumbers','Show numbers in list');
	my $sCheck6 = ::NewPrefCheckButton(OPT.'AddCurrentToStatList','Always show currently playing item in list');
	my @sum = (values %statupdatemodes);
	my $sCombo = ::NewPrefCombo(OPT.'StatViewUpdateMode',\@sum, text => 'Update Statistics: ');
	my @randoms;
	push @randoms, $_ for (sort keys %{$::Options{SavedWRandoms}});
	my $sCombo2 = ::NewPrefCombo( OPT.'StatWeightedRandomMode', \@randoms);
	my $sCheck7 = ::NewPrefCheckButton(OPT.'WeightedRandomEnabled','Enable sorting by weighted random: ');
	my $sCheck8 = ::NewPrefCheckButton(OPT.'WeightedRandomValueType','Show scaled value (0-100) of WRandom-item instead of real');
	my $sLabel1 = Gtk2::Label->new('Show images in list for:');
	$sLabel1->set_alignment(0,0.5);
	my $sCheck9a = ::NewPrefCheckButton(OPT.'StatImageArtist','Artist');
	my $sCheck9b = ::NewPrefCheckButton(OPT.'StatImageAlbum','Album');
	my $sCheck9c = ::NewPrefCheckButton(OPT.'StatImageTitle','Track');
	my $sCheck10 = ::NewPrefCheckButton(OPT.'LastfmStyleHistogram','Show histogram in \'last.fm-style\' (requires restart of plugin)');

	my @vbox = ( 
		::Vpack($gAmount1), 
		::Vpack([$hCheck1,$hCheck2],[$hCheck3,$hAmount,$hCombo],[$hAmount2,$hAmount3,$hLabel1],[$hEntry1,$hEntry2]), 
		::Vpack($oLabel1,[$oCheck1,$oCheck2,$oCheck3,$oCheck4],[$oAmount,$oAmount2],[$oCombo2,$oCombo]),
		::Vpack([$sCheck1,$sCheck4],[$sCheck2,$sCheck3],[$sCheck5,$sCheck6],[$sCheck10],$sAmount,[$sCombo],[$sCheck7,$sCombo2],$sCheck8,
				[$sLabel1,$sCheck9a,$sCheck9b,$sCheck9c]) 
	);
	
	$frame[$_]->add($vbox[$_]) for (0..$#frame);
		
	return ::Vpack($frame[0],$frame[1],$frame[2],$frame[3]);
}

sub new 
{
	my ($class,$options)=@_;
	my $self = bless Gtk2::VBox->new(0,0), $class;
	my $group= $options->{group};
	my $fontsize=$self->style->font_desc;
	$self->{fontsize} = $fontsize->get_size / Gtk2::Pango->scale;
	$self->{site} = 'history';
	$self->signal_connect(map => \&SongChanged);

	my ($Hvbox, $Hstore,$Hstore_albums) = CreateHistorySite($self);
	my ($Ovbox,$Ostore_toplist,$Ostore) = CreateOverviewSite($self,$options);	
	my ($Streeview,$Sstore,$Sinvert,$stat_hbox1,$iw,@combos,@labels) = CreateStatisticsSite($self);
	my $toolbar = CreateToolbar($self,$options);

	$self->{hstore}=$Hstore;
	$self->{hstore_albums}=$Hstore_albums;
	$self->{ostore_main}=$Ostore;
	$self->{ostore_toplist}=$Ostore_toplist;
	$self->{sstore}=$Sstore;
	$self->{butinvert} = $Sinvert;
	$self->{stattypecombo} = $combos[1];
	$self->{Ovbox} = $Ovbox;

	my $infobox = Gtk2::HBox->new; 	$infobox->set_spacing(0);
	my $site_overview = $Ovbox;
	my $site_history= $Hvbox;
	my $sh = Gtk2::ScrolledWindow->new;
	$sh->add($Streeview);
	$sh->set_shadow_type('none');
	$sh->set_policy('automatic','automatic');

	my $site_statistics = Gtk2::VBox->new(); 
	$site_statistics->pack_start($stat_hbox1,0,0,0);
	$site_statistics->pack_start($sh,1,1,0);

	$infobox->pack_start($site_history,1,1,0);
	$infobox->pack_start($site_overview,1,1,0);
	$infobox->pack_start($site_statistics,1,1,0);

	#show everything from hidden pages
	$Streeview->show; $stat_hbox1->show; $sh->show;
	$_->show for (@combos); $_->show for (@labels);
	$Sinvert->show; $iw->show;
	
	#starting site is always 'history'
	$site_overview->set_no_show_all(1);
	$site_statistics->set_no_show_all(1);

	$self->{site_overview} = $site_overview; 
	$self->{site_history} = $site_history; 
	$self->{site_statistics} = $site_statistics;

	$self->pack_start($toolbar,0,0,0);
	$self->pack_start($infobox,1,1,0);
	
	$self->{needsupdate} = 1;

	$self->signal_connect(destroy => \&DestroyCb);
	::Watch($self, CurSong => \&SongChanged);
	::Watch($self, Played => \&SongPlayed);
	::Watch($self, Filter => sub 
		{
			my $force;
			$force = 1 unless (($self->{site} eq 'history') and (!$::Options{OPT.'UseHistoryFilter'}));
			SongChanged($self,$force);
			$HistoryHash{needupdate} = 1;
		});
	
	UpdateSite($self,$self->{site});
	return $self;
}

sub CreateHistorySite
{
	## TreeView for history
	my $Hstore=Gtk2::ListStore->new('Glib::String','Glib::String','Glib::UInt','Glib::String');
	my $Htreeview=Gtk2::TreeView->new($Hstore);
	my $Hplaytime=Gtk2::TreeViewColumn->new_with_attributes( "Playtime",Gtk2::CellRendererText->new,text => 0);
	$Hplaytime->set_sort_column_id(0);
	$Hplaytime->set_resizable(1);
	$Hplaytime->set_alignment(0);
	$Hplaytime->set_min_width(10);
	my $Htrack=Gtk2::TreeViewColumn->new_with_attributes( _"Track",Gtk2::CellRendererText->new,text=>1);
	$Htrack->set_sort_column_id(1);
	$Htrack->set_expand(1);
	$Htrack->set_resizable(1);
	$Htreeview->append_column($Hplaytime);
	$Htreeview->append_column($Htrack);

	$Htreeview->get_selection->set_mode('multiple');
	$Htreeview->set_rules_hint(1);
	$Htreeview->signal_connect(button_press_event => \&HTVContext);
	$Htreeview->{store}=$Hstore;

	my $Hstore_albums=Gtk2::ListStore->new('Gtk2::Gdk::Pixbuf','Glib::String','Glib::String','Glib::UInt','Glib::String');
	my $Htreeview_albums=Gtk2::TreeView->new($Hstore_albums);
	my $Hpic=Gtk2::TreeViewColumn->new_with_attributes( "",Gtk2::CellRendererPixbuf->new,pixbuf => 0);
	$Hpic->set_sort_column_id(0);
	$Hpic->set_resizable(1);
	$Hpic->set_alignment(0);
	$Hpic->set_min_width(10);
	my $Halbum=Gtk2::TreeViewColumn->new_with_attributes( _"Album",Gtk2::CellRendererText->new,text=>1);
	$Halbum->set_sort_column_id(1);
	$Halbum->set_expand(1);
	$Halbum->set_resizable(1);
	my $Hpt=Gtk2::TreeViewColumn->new_with_attributes( _"Playtime",Gtk2::CellRendererText->new,text=>2);
	$Hpt->set_sort_column_id(2);
	$Hpt->set_expand(0);
	$Hpt->set_resizable(1);

	$Htreeview_albums->append_column($Hpic);
	$Htreeview_albums->append_column($Halbum);
	$Htreeview_albums->append_column($Hpt);
	$Htreeview_albums->get_selection->set_mode('multiple');
	$Htreeview_albums->set_rules_hint(1);
	$Htreeview_albums->signal_connect(button_press_event => \&HTVContext);
	$Htreeview_albums->{store}=$Hstore_albums;

	my $vbox = Gtk2::VBox->new;
	my $sh = Gtk2::ScrolledWindow->new;	
	$sh->add($Htreeview);
	$sh->set_shadow_type('none');
	$sh->set_policy('automatic','automatic');

	my $sh2 = Gtk2::ScrolledWindow->new;	
	$sh2->add($Htreeview_albums);
	$sh2->set_shadow_type('none');
	$sh2->set_policy('automatic','automatic');
	
	$vbox->pack_start($sh,1,1,0);
	$vbox->pack_start($sh2,1,1,0);

	return ($vbox,$Hstore,$Hstore_albums);
}

sub CreateOverviewSite
{
	my ($self,$options) = @_;
	my $vbox = Gtk2::VBox->new;

	# top-lists
	my @topheads;
	for (keys %OverviewTopheads) { push @topheads, $OverviewTopheads{$_}->{label} if $OverviewTopheads{$_}->{enabled};}
	
	my @Ostore_toplists; my @Otoptreeviews;
	
	for (0..$#topheads)
	{
		push @Ostore_toplists, Gtk2::ListStore->new('Glib::String','Glib::String','Glib::UInt','Glib::String');#label, pc, ID, field
		push @Otoptreeviews, Gtk2::TreeView->new($Ostore_toplists[$_]);
		my $Oc=Gtk2::TreeViewColumn->new_with_attributes( $topheads[$_],Gtk2::CellRendererText->new,text => 0);
		$Oc->set_expand(1);
		$Otoptreeviews[$_]->append_column($Oc);
		my $render = Gtk2::CellRendererText->new;
		#$render->set_alignment(1,.5);
		my $Opc=Gtk2::TreeViewColumn->new_with_attributes( "Playcount",$render,text => 1);
		$Opc->set_expand(0);
		$Otoptreeviews[$_]->append_column($Opc);

		$Otoptreeviews[$_]->get_selection->set_mode('single');
		$Otoptreeviews[$_]->set_rules_hint(1);
		$Otoptreeviews[$_]->set_headers_visible(1);
		$Otoptreeviews[$_]->signal_connect(button_press_event => \&HTVContext);
		$Otoptreeviews[$_]->{store}=$Ostore_toplists[$_];
		$Otoptreeviews[$_]->show;
		
		$vbox->pack_start($Otoptreeviews[$_],0,0,0);
	}

	#treeview for top40
	my $Ostore; my $Otreeview;
	# up/down/stable/new - icon (32x32?), position + lastweek position (if any), cover, label, playcount, weeks in list, GID
	$Ostore=Gtk2::ListStore->new('Gtk2::Gdk::Pixbuf','Glib::String','Gtk2::Gdk::Pixbuf','Glib::String','Glib::String','Glib::String','Glib::UInt');

	$Otreeview=Gtk2::TreeView->new($Ostore);
	my $Oicon=Gtk2::TreeViewColumn->new_with_attributes( "",Gtk2::CellRendererPixbuf->new,pixbuf => 0);
	$Oicon->set_sort_column_id(0);
	$Oicon->set_fixed_width(32);
	$Oicon->set_min_width(32);
	my $Opos=Gtk2::TreeViewColumn->new_with_attributes( "Pos",Gtk2::CellRendererText->new,text => 1);
	$Opos->set_sort_column_id(1);
	$Opos->set_expand(0);
	my $Ocover=Gtk2::TreeViewColumn->new_with_attributes( "",Gtk2::CellRendererPixbuf->new,pixbuf => 2);
	$Ocover->set_sort_column_id(0);
	$Ocover->set_fixed_width($::Options{OPT.'CoverSize'});
	$Ocover->set_min_width($::Options{OPT.'CoverSize'});
	$Ocover->set_expand(0);
	my $Olabel=Gtk2::TreeViewColumn->new_with_attributes( "Item",Gtk2::CellRendererText->new,text => 3);
	$Olabel->set_sort_column_id(1);
	$Olabel->set_expand(1);
	my $Opc=Gtk2::TreeViewColumn->new_with_attributes( "PC",Gtk2::CellRendererText->new,text => 4);
	$Opc->set_sort_column_id(1);
	$Opc->set_expand(0);
	my $Owil=Gtk2::TreeViewColumn->new_with_attributes( "IL",Gtk2::CellRendererText->new,text => 5);
	$Owil->set_sort_column_id(1);
	$Owil->set_expand(0);

#	$Otreeview->append_column($Oicon);
#	$Otreeview->append_column($Opos);
	$Otreeview->append_column($Ocover);
	$Otreeview->append_column($Olabel);
	$Otreeview->append_column($Opc);
#	$Otreeview->append_column($Owil);

	$Otreeview->get_selection->set_mode('none');
	$Otreeview->set_rules_hint(1);
	$Otreeview->set_headers_visible(1);
#	$Otreeview->signal_connect(button_press_event => \&HTVContext);
	$Otreeview->{store}=$Ostore;

	my $sh = Gtk2::ScrolledWindow->new;
	$sh->add($Otreeview);
	$sh->set_shadow_type('none');
	$sh->set_policy('automatic','automatic');
	$sh->show;
	$vbox->pack_start($sh,1,1,0);
		
	$Otreeview->show;

	# statuslabel in the bottom
	my $ago = (time-$globalstats{starttime})/86400;
	my $text = "Since ".FormatRealtime($globalstats{starttime},'%d.%m.%y');
	if ($ago)
	{
		$text .= " you have played a total of ".$globalstats{playtrack}." tracks.";
		$text .= " That's about ".int(0.5+($globalstats{playtrack}/$ago))." per day.";
	}	

	
	my $totalstatus_label = Gtk2::Label->new($text);
	$totalstatus_label->set_alignment(0,0); $totalstatus_label->show;
	$vbox->pack_end($totalstatus_label,0,0,0);
	
	return ($vbox,\@Ostore_toplists,$Ostore);
}

sub CreateStatisticsSite
{
	my $self = shift;
	
	## Treeview and little else for statistics
	my $stat_hbox1 = Gtk2::HBox->new;
	my @labels = (Gtk2::Label->new('Show'),Gtk2::Label->new('by'));
	my @lists = (undef,undef,undef); 
	push @{$lists[0]}, $StatTypes{$_}->{label} for (sort keys %StatTypes);
	for (sort keys %SortTypes){
		next if (($_ eq 'weighted_random') and (!$::Options{OPT.'WeightedRandomEnabled'})); 		
		push @{$lists[1]}, $SortTypes{$_}->{label};
	}

	my @combos; my @coptname = (OPT.'StatisticsTypeCombo',OPT.'StatisticsSortCombo');
	for (0..1) {
		$combos[$_] = ::NewPrefCombo($coptname[$_],$lists[$_]);
		$combos[$_]->signal_connect(changed => sub {Updatestatistics($self);});
		$stat_hbox1->pack_start($labels[$_],0,0,1);
		$stat_hbox1->pack_start($combos[$_],1,1,1);
	}
	
	#buttons for avg & inv
	my $Sinvert = Gtk2::ToggleButton->new();
	my $iw=Gtk2::Image->new_from_stock('gtk-sort-descending','menu');
	$Sinvert->add($iw);
	$Sinvert->set_tooltip_text('Invert sorting order');
	$Sinvert->signal_connect(toggled => sub {Updatestatistics($self);});

	$stat_hbox1->pack_start($Sinvert,0,0,0);

	# Treeview for statistics: 
	# fields in Sstore are  GID, markup, (raw)value, field, maxvalue, formattedvalue  
	my $Sstore=Gtk2::ListStore->new('Glib::ULong','Glib::String','Glib::String','Glib::String','Glib::Double','Glib::String');
	my $Streeview=Gtk2::TreeView->new($Sstore);
	
	my $Sitemrenderer=CellRendererLAITE->new;
	my $Sitem=Gtk2::TreeViewColumn->new_with_attributes( _"",$Sitemrenderer);
	$Sitem->set_cell_data_func($Sitemrenderer, sub
		{	my (undef,$cell,$store,$iter)=@_;
			
			my $gid = $store->get($iter,0); my $value = $store->get($iter,2);
			my $max = ($::Options{OPT.'LastfmStyleHistogram'})? 0 : $store->get($iter,4);
			my %hash = ($gid => $value); my $type = $store->get($iter,3);
			my $psize = $::Options{OPT.'CoverSize'};
			my $markup = $store->get($iter,1);
			$cell->set( prop => [$type,$markup,$psize], gid=>$gid, hash => \%hash, max => $max);
		});

	$Sitem->set_sort_column_id(0);
	$Sitem->set_resizable(1);	
	$Sitem->set_expand(1);
	$Sitem->set_clickable(::FALSE);
	$Sitem->set_sort_indicator(::FALSE);
	$Streeview->append_column($Sitem);

	my $Svaluerenderer=CellRendererLAITE->new;
	my $Svalue=Gtk2::TreeViewColumn->new_with_attributes( "Value",$Svaluerenderer);
	$Svalue->set_cell_data_func($Svaluerenderer, sub
		{	my (undef,$cell,$store,$iter)=@_;
			my $gid = $store->get($iter,0); my $value = $store->get($iter,2);
			my $max = ($::Options{OPT.'LastfmStyleHistogram'})? $store->get($iter,4) : 0;
			my %hash = ($gid => $value); my $type = $store->get($iter,3);
			my $psize = $::Options{OPT.'CoverSize'};
			my $markup = $store->get($iter,5);
			
			#Gtk2::Gdk::Color->new(0,32758,0)
			my $bg = ($::Options{OPT.'LastfmStyleHistogram'})? $self->style->base('normal') : undef;
			$cell->set( prop => [$type,$markup,$psize], gid=>$gid, hash => \%hash, max => $max, cell_background_gdk => $bg, nopic => 1);
		});

	$Svalue->set_sort_column_id(1);
	$Svalue->set_alignment(0);
	$Svalue->set_expand($::Options{OPT.'LastfmStyleHistogram'});
	$Svalue->set_resizable(1);
	$Svalue->set_min_width(10);
	$Svalue->set_clickable(::FALSE);
	$Svalue->set_sort_indicator(::FALSE);
	$Streeview->append_column($Svalue);
	$Streeview->set_rules_hint($::Options{OPT.'LastfmStyleHistogram'});
	my $Sselection = $Streeview->get_selection;
	$Sselection->set_mode('multiple');
	$Sselection->signal_connect(changed => \&STVChanged);
	
	$Streeview->signal_connect(button_press_event => \&STVContextPress);
	$Streeview->{store}=$Sstore;
	
	return ($Streeview,$Sstore,$Sinvert,$stat_hbox1,$iw,@combos,@labels);	
}

sub CreateToolbar
{
	my ($self,$options) = @_;
	
	## Toolbar buttons on top of widget
	my $toolbar=Gtk2::Toolbar->new;
	$toolbar->set_style( $options->{ToolbarStyle}||'both-horiz' );
	$toolbar->set_icon_size( $options->{ToolbarSize}||'small-toolbar' );
	my $radiogroup; my $menugroup;
	foreach my $key (sort keys %sites)
	{	my $item = $sites{$key}[1];
		$item = Gtk2::RadioButton->new($radiogroup,$item);
		$item->{key} = $key;
		$item -> set_mode(0); # display as togglebutton
		$item -> set_relief("none");
		$item -> set_tooltip_text($sites{$key}[2]);
		$item->set_active( $key eq $self->{site} );
		$item->signal_connect(toggled => sub { my $self=::find_ancestor($_[0],__PACKAGE__); ToggleCb($self,$item); } );
		$radiogroup = $item -> get_group;
		my $toolitem=Gtk2::ToolItem->new;
		$toolitem->add( $item );
		$toolitem->set_expand(1);
		$toolbar->insert($toolitem,-1);

	}
	
	return $toolbar;
}

sub DestroyCb
{
	return 1;
}

sub ToggleCb
{	
	my ($self, $togglebutton) = @_;
	return unless ($self->{site} ne $togglebutton->{key});

	$self->{needsupdate} = 1;
	
	if ($togglebutton -> get_active) {
		for my $key (keys %sites) {
			if ($key eq $togglebutton->{key}) {$self->{'site_'.$key}->show;}
			else {$self->{'site_'.$key}->hide;}
		}
		$self->{site} = $togglebutton->{key};
	}
	UpdateSite($self,$togglebutton->{key});
}

sub UpdateSite
{
	my ($self,$site,$force) = @_;
	return unless ((($self->{needsupdate}) or ($force)) and (defined $site));

	eval('Update'.$site.'($self);');
	if ($@) { warn "Bad eval in Historystats::UpdateSite()! Site: ".$site.", ERROR: ".$@;}

	$self->{needsupdate} = 0;

	return 1;
}

sub Updatestatistics
{
	my $self = shift;

	my ($field) = grep { $StatTypes{$_}->{label} eq $::Options{OPT.'StatisticsTypeCombo'}} keys %StatTypes;
	my ($sorttype) = grep { $SortTypes{$_}->{label} eq $::Options{OPT.'StatisticsSortCombo'}} keys %SortTypes;

	return unless (($field) and ($sorttype));

	my $suffix = $SortTypes{$sorttype}->{suffix};
	$field = $StatTypes{$field}->{field};
	$sorttype = $SortTypes{$sorttype}->{typecode};
	my $source = (defined $::SelectedFilter)? $::SelectedFilter->filter : $::Library;
	my @list; my $dh; my $dotime; my $maxvalue;my $max;

	$self->{sstore}->clear;
	
	#calculate album-based stats if so wanted
	if (($field !~ /album|title/) and ($::Options{OPT.'PerAlbumInsteadOfTrack'}) and ($suffix eq ':average') and ($sorttype ne 'weighted'))
	{
		($dh) = Songs::BuildHash($field, $source, undef, $sorttype.':sum');
		my ($ah) = Songs::BuildHash('album', $source, undef, $sorttype.':average');
		for my $gid (keys %$dh) {
			my $albums = AA::Get('album:gid',$field,$gid);
			next unless (scalar@$albums);
			$$dh{$gid} = 0;
			my $ok=0;
			for (@$albums) {
				my $ilist = AA::Get($field.':gid','album',$_);
				next unless ((ref($ilist) ne 'ARRAY') or ((scalar@$ilist == 1) and ($$ilist[0] == $gid)));
				$$dh{$gid} += $$ah{$_};
				$ok++;
			}
			$$dh{$gid} /= $ok unless (!$ok);
		}
	}
	else {
		if ($sorttype eq 'weighted')
		{
			my $randommode = Random->new(${$::Options{SavedWRandoms}}{$::Options{OPT.'StatWeightedRandomMode'}},$source);
			my $sub = ($field eq 'title')? $randommode->MakeSingleScoreFunction() : $randommode->MakeGroupScoreFunction($field);
			($dh)=$sub->($source);
			ScaleWRandom(\%$dh,$field);
			
		}
		else{
			if ($field ne 'title') {($dh) = Songs::BuildHash($field, $source, undef, $sorttype.$suffix);}
			else {
				@list = @$source;
				Songs::SortList(\@list,'-'.$sorttype);
				if ($self->{butinvert}->get_active) { @list = reverse @list;}
				$max = ($::Options{OPT.'AmountOfStatItems'} < (scalar@list))? ($::Options{OPT.'AmountOfStatItems'}) : (scalar@list);
				$$dh{$list[$_]} = Songs::Get($list[$_],$sorttype) for (0..($max-1));
				@list = ();#empty list for now, just to be sure
			}
		} 
	}
	#we got values, send 'em up!
	$max = ($::Options{OPT.'AmountOfStatItems'} < (keys %$dh))? $::Options{OPT.'AmountOfStatItems'} : (keys %$dh);
	my $currentID = ($::SongID)? (($field eq 'title')? $::SongID : Songs::Get_gid($::SongID,$field)) : -1; 
	@list = (sort { ($self->{butinvert}->get_active)? $dh->{$a} <=> $dh->{$b} : $dh->{$b} <=> $dh->{$a} } keys %$dh)[0..($max-1)];
			
	if ($::Options{OPT.'AddCurrentToStatList'})
	{
		my @cis;
		if (ref($currentID) ne 'ARRAY') { push @cis, $currentID;}
		else {@cis = @$currentID;}
	
		for my $ci (@cis){
			next if ($ci == -1);
			if (scalar@$source != scalar@$::Library){
				my ($isin) = grep { $ci == $$source[$_] } 0..$#$source;
				next unless (defined $isin);
			}
			my ($iscurrentIDinlist)= grep { $ci == $list[$_]} 0..$#list;
			push @list, $ci unless (defined $iscurrentIDinlist);
		}
	}

	#maxvalue is either first or last item in list (also applies when added current song in list)		
	$maxvalue = ($$dh{$list[$#list]} > $$dh{$list[0]})? $$dh{$list[$#list]} : $$dh{$list[0]};
	
	for (0..$#list)
	{
		my $value = $dh->{$list[$_]}; my $formattedvalue;
			if ($sorttype eq 'playedlength') { $formattedvalue = FormatSmalltime($dh->{$list[$_]});}
		else {$formattedvalue = ($suffix =~ /average/)? sprintf ("%.2f", $dh->{$list[$_]}) : $dh->{$list[$_]};}
		
		my $num = ($_ > ($max-1))? "n/a  " : undef; #this is for the current, if it's not in original list  
		$num ||= ($::Options{OPT.'ShowStatNumbers'})? (($_+1).".   ") : " ";
		$self->{sstore}->set($self->{sstore}->append,
				0,$list[$_],
				1,HandleStatMarkup($field,$list[$_],$num),
				2,$value,3,$field,
				4,$maxvalue,5,$formattedvalue);
	}

	return 1;
}

sub Updateoverview
{
	my $self = shift;
	my @list;

	$_->clear for (@{$self->{ostore_toplist}});
	my @topheads; 
	for (keys %OverviewTopheads) { push @topheads, $_ if ($OverviewTopheads{$_}->{enabled});};
	my $numberofitems;
	
	for my $store (0..$#topheads)
	{
		my $topref;
		if ($topheads[$store] eq 'title')
		{
			my $lr = $::Library;
			my $smode = ($::Options{OPT.'OverviewTopMode'}); $smode =~ s/\:(.+)//;
			Songs::SortList($lr,'-'.$smode);
			$numberofitems = ($::Options{OPT.'OverViewTopAmount'} > (scalar@$lr))? (scalar@$lr) : $::Options{OPT.'OverViewTopAmount'};
			@list = @$lr[0..($::Options{OPT.'OverViewTopAmount'})];
		}
		else
		{
			($topref) = Songs::BuildHash($topheads[$store],$::Library,undef,$::Options{OPT.'OverviewTopMode'});
			$numberofitems = ($::Options{OPT.'OverViewTopAmount'} > (keys %$topref))? (keys %$topref) : $::Options{OPT.'OverViewTopAmount'};
			@list = ((sort { $topref->{$b} <=> $topref->{$a} } keys %$topref)[0..($numberofitems-1)]);
		}
		for my $row (0..($numberofitems-1))
		{
			my @values;
			if ($topheads[$store] eq 'title') {
				my $smode = ($::Options{OPT.'OverviewTopMode'}); $smode =~ s/\:(.+)//;
				my ($title,$value) = Songs::Get($list[$row],'title',$smode);
				push @values, 0,$title,1,$value.' plays',2,$list[$row],3,$topheads[$store];
			}
			else {
				push @values, 0,Songs::Gid_to_Display($topheads[$store],$list[$row]),1,$$topref{$list[$row]}.' plays',2,$list[$row],3,$topheads[$store];
			}

			${$self->{ostore_toplist}}[$store]->set(${$self->{ostore_toplist}}[$store]->append,@values);
		}
	}
	
	
	# Main Chart
	#TODO: Handle properly with @playtimes when possible, for now we'll just put TopNN items here
	my %fc = (Artists => 'artist', Albums => 'album', Tracks => 'title');
	my $dh; my $max; my $field = $fc{$::Options{OPT.'OverviewTop40Item'}} || 'album';
	
	unless($field eq 'title'){
		($dh) = Songs::BuildHash($field, $::Library, undef, 'playcount:sum');
		$max = ($::Options{OPT.'OverviewTop40Amount'} < (keys %$dh))? $::Options{OPT.'OverviewTop40Amount'} : (keys %$dh);
		@list = (sort { $dh->{$b} <=> $dh->{$a} } keys %$dh)[0..($max-1)];
	}
	else {
		@list = @$::Library;
		Songs::SortList(\@list,'-playcount'); 
		$max = ($::Options{OPT.'OverviewTop40Amount'} < (scalar@list))? $::Options{OPT.'OverviewTop40Amount'} : (scalar@list);
	}
	$self->{ostore_main}->clear;
	my $icon = $self->render_icon("gtk-add","menu");
	for (0..$#list){
		my $label; my $value; my $pic; 
	
		if ($field eq 'title'){
			($label,$value) = Songs::Get($list[$_],qw/title playcount/);
			$pic = AAPicture::pixbuf('album', Songs::Get_gid($list[$_],'album'), $::Options{OPT.'CoverSize'}, 1);	
		}
		else{
			$label = Songs::Gid_to_Display($field,$list[$_]);
			$value = $$dh{$list[$_]};
			$pic = AAPicture::pixbuf($field, $list[$_], $::Options{OPT.'CoverSize'}, 1);
		}
		
		$self->{ostore_main}->set($self->{ostore_main}->append,
			0,$icon,
			1,$_,
			2,$pic,
			3,($_+1).' - '.$label,
			4,$value,
			5,'-',
			6,$list[$_]	
		);
	}
	
	return 1;
}

sub Updatehistory
{
	my $self = shift;

	if ($HistoryHash{needupdate})
	{
		delete $sourcehash{$_} for (keys %sourcehash);
		my $source = (($::Options{OPT.'UseHistoryFilter'}) and (defined $::SelectedFilter))? $::SelectedFilter->filter : $::Library; 
		$sourcehash{$$source[$_]} = $_ for (0..$#$source);
		delete $HistoryHash{needupdate};
	}

	CreateHistory() if ((!scalar keys %HistoryHash) or ($HistoryHash{needrecreate}));

	my $amount; my $lasttime = 0;
	if ($::Options{OPT.'HistoryLimitMode'} eq 'days') {
		$lasttime = time-(($::Options{OPT.'AmountOfHistoryItems'}-1)*86400);
		my ($sec, $min, $hour) = (localtime(time))[0,1,2];
		$lasttime -= ($sec+(60*$min)+(3600*$hour));
	}
	else{$amount = ((scalar keys(%HistoryHash)) < $::Options{OPT.'AmountOfHistoryItems'})? scalar keys(%HistoryHash) : $::Options{OPT.'AmountOfHistoryItems'};}

	my %final; my %seen_alb; my %albumplaytimes; my @albumorder;
	
	#we test from biggest to smallest playtime (keys are 'pt'.$playtime) until find $amount songs that are in source
	for my $hk (reverse sort keys %HistoryHash) 
	{
		if ($hk =~ /^pt(\d+)$/) { last unless ($1 > $lasttime);}
		if (defined $sourcehash{$HistoryHash{$hk}->{ID}}) {
			$final{$hk} = $HistoryHash{$hk};
			$amount-- if (defined $amount);

			my $gid = Songs::Get_gid($final{$hk}->{ID},'album');
			push @{$seen_alb{$gid}}, $final{$hk}->{ID};
			if ((not defined $albumplaytimes{$gid}) and ($hk =~ /^pt(\d+)$/)){$albumplaytimes{$gid} = $1; push @albumorder,$gid;}
		}
		last if ((defined $amount) and ($amount <= 0));
	}

	#then re-populate the hstore
	$self->{hstore}->clear;
	for (reverse sort keys %final)	{
		my $key = $_;
		$key =~ s/^pt//;
		$self->{hstore}->set($self->{hstore}->append,0,FormatRealtime($key),1,$final{$_}->{label},2,$final{$_}->{ID},3,'song');
	}
	
	# then albums
	$self->{hstore_albums}->clear;
	
	my @real_source; my @playedsongs;
	for my $key (@albumorder) {
		push @real_source, @{AA::Get('idlist','album',$key)};
		push @playedsongs, @{$seen_alb{$key}};
	}
	my ($totallengths) = Songs::BuildHash('album', \@real_source, undef, 'length:sum');
	my ($playedlengths) = Songs::BuildHash('album', \@playedsongs, undef, 'length:sum');

	for my $key (@albumorder) 
	{
		#don't add album if treshold doesn't hold
		next unless ((($$playedlengths{$key}*100)/$$totallengths{$key} > $::Options{OPT.'HistAlbumPlayedPerc'}) or (($$playedlengths{$key}/60) > $::Options{OPT.'HistAlbumPlayedMin'}));

		my $xref = AA::Get('album_artist:gid','album',$key);
		$self->{hstore_albums}->set($self->{hstore_albums}->append,
			0,AAPicture::pixbuf('album', $key, $::Options{OPT.'CoverSize'}, 1),
			1,Songs::Gid_to_Display('album',$key)."\n by ".Songs::Gid_to_Display('artist',$$xref[0]),
			2,FormatRealtime($albumplaytimes{$key}),
			3,$key,
			4,'album');
	}	
		
	return 1;	 
}

sub CreateHistory
{
	for my $ID (@$::Library)
	{
		my $pt = Songs::Get($ID,'lastplay');
		next unless ($pt);#we use playtime as hash key, so it must exist

		$HistoryHash{'pt'.$pt}{ID} = $ID;
		$HistoryHash{'pt'.$pt}{label} = ::ReplaceFields($ID,$::Options{OPT.'HistoryItemFormat'} || '%a - %l - %t');
	}

	delete $HistoryHash{needrecreate} if ($HistoryHash{needrecreate});

	return 1;
}

sub FormatSmalltime
{
	my $sec = shift;

	my $result = '';
	
	if ($sec > 31536000) { $result .= int($sec/31536000).'y '; $sec = $sec%31536000;}
	if ($sec > 2592000) { $result .= int($sec/2592000).'m '; $sec = $sec%2592000;}
	elsif ($sec > 604800) { $result .= int($sec/604800).'wk ';} #show either weeks or months, not both
	$sec = $sec%604800;
	if ($sec > 86400) { $result .= int($sec/86400).'d '; $sec = $sec%86400;}
	$result .= sprintf("%02d",int(($sec%86400)/3600)).':'.sprintf("%02d",int(($sec%3600)/60)).':'.sprintf("%02d",int($sec%60));

	return $result;
}
sub FormatRealtime
{
	my ($realtime,$format) = @_;
	return 'n/a' unless ($realtime);
	my @months = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
	my ($sec, $min, $hour, $day,$month,$year) = (localtime($realtime))[0,1,2,3,4,5]; 	
	$month += 1; $year += 1900;
	my $h12 = ($hour > 11)? $hour-12 : $hour;
	my $ind = ($hour > 11)? 'pm' : 'am';
	$hour = sprintf("%02d",$hour);
	$min = sprintf("%02d",$min);
	$sec = sprintf("%02d",$sec);
	
	my $formatted;
	if ((defined $format) or (defined $::Options{OPT.'HistoryTimeFormat'}))
	{
		$formatted = $format || $::Options{OPT.'HistoryTimeFormat'};
		$formatted =~ s/\%[^dmyHhMSp]//g;
		$formatted =~ s/\%d/$day/g; $formatted =~ s/\%m/$month/g;	
		$formatted =~ s/\%y/$year/g;	$formatted =~ s/\%H/$hour/g;	
		$formatted =~ s/\%h/$h12/g; $formatted =~ s/\%M/$min/g;	
		$formatted =~ s/\%S/$sec/g; $formatted =~ s/\%p/$ind/g;	
	}
	else {$formatted = "".localtime($realtime);}

	return $formatted;
}

sub HandleStatMarkup
{
	my ($field,$id,$listnum) = @_;
	my $markup = ($field eq 'title')? $listnum."%t": $listnum."%a";	
	
	if ($::SongID){
		my $nowplaying = ($field eq 'title')? $::SongID : Songs::Get_gid($::SongID,$field);
		if (ref($nowplaying) eq 'ARRAY') { for (@$nowplaying) {if ($_ == $id) {$markup = '<b>'.$markup.'</b>';}}}
		elsif ($nowplaying == $id) { $markup = '<b>'.$markup.'</b>';}
	}

	if (($::Options{OPT.'ShowArtistForAlbumsAndTracks'}) and ($field =~ /album|title/))
	{
		my $HasPic = ($::Options{'PLUGIN_HISTORYSTATS_StatImage'.ucfirst($field)})? 1 : 0;
		if ($field eq 'album') {
			if ($HasPic) {$markup = $markup."\n\t by ".::PangoEsc(Songs::Gid_to_Display('artist',@{AA::Get('album_artist:gid','album',$id)}[0]));}
			else {$markup = $markup."<small>  by  ".::PangoEsc(Songs::Gid_to_Display('artist',@{AA::Get('album_artist:gid','album',$id)}[0])).'</small>';}
		}
		elsif ($field eq 'title'){
			if ($HasPic) { $markup = $markup."\n\t by %a";}
			else {$markup = $markup."<small> by %a </small>"}
		}
	}
	
	return $markup;
}

sub UpdateCursorCb
{	
	my $textview = shift;
	my (undef,$wx,$wy,undef)=$textview->window->get_pointer;
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$wx,$wy);
	my $iter=$textview->get_iter_at_location($x,$y);
	my $cursor='xterm';
	for my $tag ($iter->get_tags)
	{	next unless $tag->{gid};
		$cursor='hand2';
		last;
	}
	return if ($textview->{cursor}||'') eq $cursor;
	$textview->{cursor}=$cursor;
	$textview->get_window('text')->set_cursor(Gtk2::Gdk::Cursor->new($cursor));
}

sub ButtonReleaseCb
{
	my ($textview,$event) = @_;
	
	my $self=::find_ancestor($textview,__PACKAGE__);
	my ($x,$y)=$textview->window_to_buffer_coords('widget',$event->x, $event->y);
	my $iter=$textview->get_iter_at_location($x,$y);
	for my $tag ($iter->get_tags) {	
		my $gid = $tag->{gid}; my $field = $tag->{field};
		if ($field ne 'title') {
			::PopupAAContextMenu({gid=>$gid,self=>$textview,field=>$field,mode=>'S'});
		}
		else{
			::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $textview, IDs => [$gid]});
		}
	}

	return ::TRUE; #don't want any default popups
}

sub HTVContext 
{
	my ($treeview, $event) = @_;
	return 0 unless $treeview;

	my @paths = $treeview->get_selection->get_selected_rows;
	return unless (scalar@paths);

	my $store=$treeview->{store};
	my @IDs; my $field;# this will be same for all rows, either 'song' or 'album'
	
	for (@paths)
	{
		my $iter=$store->get_iter($_);
		my $ID=$store->get( $store->get_iter($_),3);
		$field=$store->get( $store->get_iter($_),4);
		push @IDs,$ID;
	}

	if ($event->button == 2) { 
		if ($field eq 'song') {::Enqueue(\@IDs);}
		else {}		 
	}
	elsif ($event->button == 3) {
		if ($field ne 'song')
		{
			if (scalar@IDs == 1) {::PopupAAContextMenu({gid=>$IDs[0],self=>$treeview,field=>$field,mode=>'S'});}
			else {
				my @idlist;
				for (@IDs) {push @idlist , @{AA::Get('idlist',$field,$_)};}
				::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $treeview, IDs => \@idlist});
			}
		}
		else {::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $treeview, IDs => \@IDs});}			
	}
	elsif (($event->button == 1) and ($event->type  eq '2button-press') and (scalar@IDs == 1)) {
		if ($field ne 'title'){
			my $aalist = AA::Get('idlist',$field,$IDs[0]);
			Songs::SortList($aalist,$::Options{Sort} || $::Options{Sort_LastOrdered});
			::Select( filter => Songs::MakeFilterFromGID($field,$IDs[0])) if ($::Options{OPT.'FilterOnDblClick'});
			::Select( song => $$aalist[0], play => 1);
		}
		else {::Select(song => $IDs[0], play => 1);}
	}
	else {return 0;}
	
	return 1;
}

sub STVContextPress
{
	my ($treeview, $event) = @_;
	return 0 unless $treeview;

	my $store=$treeview->{store};
	my @paths = $treeview->get_selection->get_selected_rows;

	return unless (scalar@paths);
	my @IDs; my $field;
	
	for (@paths)
	{
		my $iter=$store->get_iter($_);
		my $ID=$store->get( $store->get_iter($_),0);
		$field=$store->get( $store->get_iter($_),3);
		push @IDs,$ID;
	}

	if ($event->button == 3)
	{
		if ($field ne 'title'){
			if (scalar@IDs == 1) {::PopupAAContextMenu({gid=>$IDs[0],self=>$treeview,field=>$field,mode=>'S'});}
			else {
				my @idlist;
				for (@IDs) {push @idlist , @{AA::Get('idlist',$field,$_)};}
				::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $treeview, IDs => \@idlist});
			}
		}
		else {
			::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $treeview, IDs => \@IDs});
		}
	}
	elsif (($event->button == 1) and ($event->type  eq '2button-press') and (scalar@IDs == 1)) {
		if ($field ne 'title'){
			my $aalist = AA::Get('idlist',$field,$IDs[0]);
			Songs::SortList($aalist,$::Options{Sort} || $::Options{Sort_LastOrdered});
			::Select( filter => Songs::MakeFilterFromGID($field,$IDs[0])) if ($::Options{OPT.'FilterOnDblClick'});
			::Select( song => $$aalist[0], play => 1);
		}
		else { ::Select(song => $IDs[0], play => 1);}
	}
	else { return 0;}
	
	return 1;
}

sub STVChanged
{
	my $treeselection = shift;
	
	return unless ($::Options{OPT.'SetFilterOnLeftClick'});
	
	my $treeview = $treeselection->get_tree_view;	
	my $store=$treeview->{store};
	my @paths = $treeview->get_selection->get_selected_rows;
	
	return unless (scalar@paths);
	my @Filters; my $field;
	
	for (@paths)
	{
		my $iter=$store->get_iter($_);
		my $GID=$store->get( $store->get_iter($_),0);
		$field=$store->get( $store->get_iter($_),3);
		next if ($field eq 'title');
		push @Filters, Songs::MakeFilterFromGID($field,$GID);
	}
	
	my $fnew = Filter->newadd(0, @Filters);
	my $filt = (defined $::SelectedFilter)? Filter->newadd(1,$::SelectedFilter,$fnew) : $fnew; 
	
	::SetFilter($treeview,$filt,1);
	
	return 1;
}

sub SongChanged 
{
	my ($widget,$force) = @_;
	
	return if (($lastID == $::SongID) and (!$force));
	
	my $albumhaschanged = (Songs::Get_gid($lastID,'album') != Songs::Get_gid($::SongID,'album'))? 1 : 0; 
	
	$lastID = $::SongID;
	
	my $self=::find_ancestor($widget,__PACKAGE__);
	
	if ($self->{site} eq 'statistics')
	{
		$force = 1 if (($::Options{OPT.'StatViewUpdateMode'} eq $statupdatemodes{songchange}) 
						or 
					  (($::Options{OPT.'StatViewUpdateMode'} eq $statupdatemodes{albumchange}) and ($albumhaschanged)));
	} 

	UpdateSite($self,$self->{site},$force);
	
	return 1;
}
sub SongPlayed
{
	my ($self,$ID, $playedEnough, $StartTime, $seconds, $coverage_ratio, $Played_segments) = @_;

	AddToHistory($self,$ID,$StartTime) if (($playedEnough) or ((!$::Options{OPT.'RequirePlayConditions'}) and ($lastAdded{ID} != $ID))); 

	$::Options{OPT.'TotalPlayTime'} = $globalstats{playtime}+$seconds; 
	$::Options{OPT.'TotalPlayTracks'} = ($globalstats{playtrack}+1) if ($playedEnough);
	$globalstats{playtime} = $::Options{OPT.'TotalPlayTime'};
	$globalstats{playtrack} = $::Options{OPT.'TotalPlayTracks'};

	if ($lastAdded{albumID} != Songs::Get_gid($lastAdded{ID},'album'))
	{
		
	}
	
	return 1;
}

sub AddToHistory
{
	my ($self,$ID,$playtime) = @_;	

	$lastAdded{ID} = $ID;
	$lastAdded{playtime} = $playtime;
	
	$HistoryHash{'pt'.$playtime}{ID} = $ID;
	$HistoryHash{'pt'.$playtime}{label} = join " - ", ::ReplaceFields($ID,$::Options{OPT.'HistoryItemFormat'} || '%a - %l - %t');

	$self->{needsupdate} = ($self->{site} eq 'history')? 1 : 0;
	UpdateSite($self,'history');

	LogHistory($ID,$playtime) if ($::Options{OPT.'LogHistoryToFile'});
	
	return 1;
}

sub LogHistory
{
	my ($ID,$playtime) = @_;
	return unless (($ID) and ($playtime));
	
	my $content = FormatRealtime($playtime)."\t".::ReplaceFields($ID,$::Options{OPT.'HistoryItemFormat'} || '%a - %l - %t');
		
	open my $fh,'>>',$LogFile or warn "Error opening '$LogFile' for writing : $!\n";
	print $fh $content   or warn "Error writing to '$LogFile' : $!\n";
	close $fh;

	return 1;	
}

sub Random::MakeSingleScoreFunction
{	my $self=shift;
	my @Score;
	$self->{Slist}=\@Score;
	my ($before,$score)=$self->make;
	my $func= $before.'; sub {my %s; $s{$_}='.$score.' for @{$_[0]}; return \%s; }';
	my $sub=eval $func;
	if ($@) { warn "Error in eval '$func' :\n$@"; $Score[$_]=1 for @{$_[0]}; }
	return $sub;
}

sub ScaleWRandom
{
	my ($dh,$field) = @_;

	my $min;my $max;
	for (keys %{$dh}){
		my $list = ($field eq 'title')? [$_] : AA::GetIDs($field,$_);
		next unless (scalar@$list);
		$$dh{$_} /= scalar@$list; #we want only average values
		if ((not defined $min) or ($$dh{$_} < $min)) {$min = $$dh{$_};}
		elsif ((not defined $max) or ($$dh{$_} > $max)) {$max = $$dh{$_};}
	}
	
	if ($::Options{OPT.'WeightedRandomValueType'}) #calculate scaled value (1-100)
	{
		for (keys %{$dh}) {
			$$dh{$_} = ($max == $min)? 100 : ($$dh{$_}-$min)*(100/($max-$min));
		}
	}

	return 1;
}

package CellRendererLAITE;
use Glib::Object::Subclass 'Gtk2::CellRenderer',
properties => [ Glib::ParamSpec->ulong('gid', 'gid', 'group id',		0, 2**32-1, 0,	[qw/readable writable/]),
		Glib::ParamSpec->boolean('nopic', 'nopic', 'nopic',	0, [qw/readable writable/]),
		Glib::ParamSpec->ulong('all_count', 'all_count', 'all_count',	0, 2**32-1, 0,	[qw/readable writable/]),
		Glib::ParamSpec->double('max', 'max', 'max value of bar',	0, 2**32-1, 0,	[qw/readable writable/]),
		Glib::ParamSpec->scalar('prop', 'prop', '[[field],[markup],[picsize]]',		[qw/readable writable/]),
		Glib::ParamSpec->scalar('hash', 'hash', 'gid to value',			[qw/readable writable/]),
		];
use constant { PAD => 2, XPAD => 2, YPAD => 2,		P_FIELD => 0, P_MARKUP =>1, P_PSIZE=>2, P_ICON =>3, P_HORIZON=>4 };

sub makelayout
{	my ($cell,$widget)=@_;
	my ($prop,$gid)=$cell->get(qw/prop gid/);
	my $layout=Gtk2::Pango::Layout->new( $widget->create_pango_context );
	my $field=$prop->[P_FIELD];
	my $markup=$prop->[P_MARKUP];# || "%a";
	if ($markup !~ /\%/){ $markup = ::PangoEsc($markup);}
	elsif ($field eq 'title') { $markup = ::ReplaceFields($gid,$markup,::TRUE);}
	else { $markup=AA::ReplaceFields( $gid,$markup,$field,::TRUE ); }
	$layout->set_markup($markup);
	return $layout;
}

sub GET_SIZE
{	my ($cell, $widget, $cell_area) = @_;
	my $layout=$cell->makelayout($widget);
	my ($w,$h)=$layout->get_pixel_size;
	my ($prop)=$cell->get('prop');
	my ($nopic)=$cell->get('nopic');
	my $ICanHasPic = ($::Options{'PLUGIN_HISTORYSTATS_StatImage'.ucfirst($prop->[P_FIELD])})? 1 : 0;
	my $s= $prop->[P_PSIZE] || $prop->[P_ICON] || 0;
	if ((!$ICanHasPic) or ($s == -1)) {$s=0}
	elsif ($h<$s)	{$h=$s}
	my $width= $prop->[P_HORIZON] ? $w+$s+PAD+XPAD*2 : 0;
	return (0,0,$width,$h+YPAD*2);
}

sub RENDER
{	my ($cell, $window, $widget, $background_area, $cell_area, $expose_area, $flags) = @_;
	my $x=$cell_area->x+XPAD;
	my $y=$cell_area->y+YPAD;
	my ($prop,$gid,$hash,$max,$nopic)=$cell->get(qw/prop gid hash max nopic/);
	my $iconfield= $prop->[P_ICON];
	my $ICanHasPic = ($::Options{'PLUGIN_HISTORYSTATS_StatImage'.ucfirst($prop->[P_FIELD])})? 1 : 0;
	my $psize= $iconfield ? (Gtk2::IconSize->lookup('menu'))[0] : $prop->[P_PSIZE];
	my $layout=$cell->makelayout($widget);
	my ($w,$h)=$layout->get_pixel_size;
	$psize=0 if (($psize == -1) or (!$ICanHasPic));
	$w+=PAD+$psize;
	my $offy=0;
	if ($psize>$h)
	{	$offy+=int( $cell->get('yalign')*($psize-$h) );
		$h=$psize;
	}
	my $state= ($flags & 'selected') ?
		( $widget->has_focus			? 'selected'	: 'active'):
		( $widget->state eq 'insensitive'	? 'insensitive'	: 'normal');

	if (($psize) and ($ICanHasPic) and (!$nopic))
	{	
		my $field=$prop->[P_FIELD];
		my $pixbuf=	$iconfield	? $widget->render_icon(Songs::Picture($gid,$field,'icon'),'menu')||undef: #FIXME could be better
						AAPicture::pixbuf($field,$gid,$psize);
		if ($pixbuf) #pic cached -> draw now
		{	my $offy=int(($h-$pixbuf->get_height)/2);#center pic
			my $offx=int(($psize-$pixbuf->get_width)/2);
			$window->draw_pixbuf( $widget->style->black_gc, $pixbuf,0,0,
				$x+$offx, $y+$offy,-1,-1,'none',0,0);
		}
		elsif (defined $pixbuf) #pic exists but not cached -> load and draw in idle
		{	my ($tx,$ty)=$widget->widget_to_tree_coords($x,$y);
			$cell->{idle}||=Glib::Idle->add(\&idle,$cell);
			$cell->{widget}||=$widget;
			$cell->{window}||=$window;
			$cell->{queue}{$ty}=[$tx,$ty,$gid,$psize,$h,\$field];
		}
	}

	my $startx;
	my $lstate = $state;
	if (($max) and (!($flags & 'selected')) and ($hash->{$gid}))
	{	
		my $maxwidth = ($background_area->width) - XPAD;
		$maxwidth-= $psize unless ($nopic);
		$maxwidth=5 if $maxwidth<5;

		my $width= ((100*$hash->{$gid}) / $max) * $maxwidth / 100;
		$width = ::max($width,int($maxwidth/5));
		
		$startx = ($::Options{'PLUGIN_HISTORYSTATS_LastfmStyleHistogram'})? $cell_area->x : $x+$psize+XPAD;
		$lstate = 'selected' if ($::Options{'PLUGIN_HISTORYSTATS_LastfmStyleHistogram'});
		$widget->style->paint_flat_box( $window,$lstate,'none',$expose_area,$widget,'',
			$startx, $cell_area->y, $width, $cell_area->height );
	}
	
	$startx = (defined $startx)? $startx+PAD+XPAD : $x+$psize+PAD+XPAD;
	# draw text
	$widget-> get_style-> paint_layout($window, $lstate, 1,
		$background_area, $widget, undef, $startx, $y+$offy, $layout);

}

sub reset
{	my $cell=$_[0];
	delete $cell->{queue};
	Glib::Source->remove( $cell->{idle} ) if $cell->{idle};
	delete $cell->{idle};
}

sub idle
{	my $cell=$_[0];
	{	last unless $cell->{queue} && $cell->{widget}->mapped;
		my ($y,$ref)=each %{ $cell->{queue} };
		last unless $ref;
		delete $cell->{queue}{$y};
		_drawpix($cell->{widget},$cell->{window},@$ref);
		last unless scalar keys %{ $cell->{queue} };
		return 1;
	}
	delete $cell->{queue};
	delete $cell->{widget};
	delete $cell->{window};
	return $cell->{idle}=undef;
}

sub _drawpix
{	my ($widget,$window,$ctx,$cty,$gid,$psize,$h,$fieldref)=@_;
	my ($vx,$vy,$vw,$vh)=$widget->get_visible_rect->values;
	#warn "   $gid\n";
	return if $vx > $ctx+$psize || $vy > $cty+$h || $vx+$vw < $ctx || $vy+$vh < $cty; #no longer visible
	#warn "DO $gid\n";
	my ($x,$y)=$widget->tree_to_widget_coords($ctx,$cty);
	my $pixbuf= AAPicture::pixbuf($$fieldref,$gid, $psize,1);
	return unless $pixbuf;

	my $offy=int( ($h-$pixbuf->get_height)/2 );#center pic
	my $offx=int( ($psize-$pixbuf->get_width )/2 );
	$window->draw_pixbuf( $widget->style->black_gc, $pixbuf,0,0,
		$x+$offx, $y+$offy, -1,-1,'none',0,0);
}



1