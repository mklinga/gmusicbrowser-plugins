# Gmusicbrowser: Copyright (C) 2005-2011 Quentin Sculo <squentin@free.fr>
# History/Stats: Copyright (C) Markus Klinga (laite) <laite@gmx.com>
#
# This file is a plugin to Gmusicbrowser.
# It is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3, as
# published by the Free Software Foundation.

# TODO:
# - mainchart with top artist & their top albums?
# - do we really need to save whole label with playchart.history?
#
# BUGS:
# - gmb-artist doesn't show?
# 

=gmbplugin HISTORYSTATS
name	History/Stats
title	History/Stats - plugin
version 0.01
desc	Show playhistory and statistics in layout
=cut

package GMB::Plugin::HISTORYSTATS;
my $VNUM = '0.01';

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
	HistoryItemFormat => '%a - %l - %t',FilterOnDblClick => 1, LogHistoryToFile => 0, SetFilterOnLeftClick => 1,
	PerAlbumInsteadOfTrack => 0, ShowStatNumbers => 1, AddCurrentToStatList => 1, OverviewTopMode => 'playcount:sum',
	OverViewTopAmount => 5, CoverSize => 60, StatisticsTypeCombo => 'Artists', OverviewTop40Mode => 'last week',
	StatisticsSortCombo => 'Playcount (Average)', OverviewTop40Amount => 40, WeightedRandomEnabled => 1, WeightedRandomValueType => 1,
	StatImageArtist => 1, StatImageAlbum => 1, StatImageTitle => 1, OverviewTop40Item => 'Albums', LastfmStyleHistogram => 0,
	HistAlbumPlayedPerc => 50, HistAlbumPlayedMin => 40, TimePeriodCombo => 'Overall', ShowOverviewIcon => 1, ShowOverviewHistory => 1
);

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

my %OverviewChartIcons = (
	down => {stock => 'gtk-go-down'},
	same => {stock => 'gtk-go-next'},
	first => {stock => 'gtk-about'},
	up => {stock => 'gtk-go-up'},
	reappear => {stock => 'edit-redo'},
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

my %timeperiods = (
	a => { label => 'last week', dayspan => 'w'},
	b => { label => 'last month', dayspan => 'm'},
	c => { label => '1 week', dayspan => 7},
	d => { label => '2 weeks', dayspan => 14},
	e => { label => '4 weeks', dayspan => 28},
	f => { label => '3 months', dayspan => 90},
	g => { label => '6 months', dayspan => 180},
	h => { label => '12 months', dayspan => 365},
	i => { label => 'Overall', dayspan => 'o'},
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
my $ChartFile = $::HomeDir.'playcharts.history';
my %sourcehash;
my $lastID = -1; 
my %lastAdded = ( ID => -1, playtime => -1, albumID => -1);
my $lastPlaytime;
my %globalstats;
my %ChartHistory;
my $merging = 0;

sub Start {
	Layout::RegisterWidget(HistoryStats => $statswidget);
	if (not defined $::Options{OPT.'StatisticsStartTime'}) {
		$::Options{OPT.'StatisticsStartTime'} = time;
	}
	$::Options{OPT.'StatWeightedRandomMode'} = ((sort keys %{$::Options{SavedWRandoms}})[0]) unless (defined $::Options{OPT.'StatWeightedRandomMode'});

	$globalstats{starttime} = $::Options{OPT.'StatisticsStartTime'}; 
	$globalstats{playtime} = $::Options{OPT.'TotalPlayTime'};
	$globalstats{playtrack} = $::Options{OPT.'TotalPlayTracks'};
	
	for (sort keys %OverviewTopheads) { 
		if (defined $::Options{OPT.'OVTH'.$_}) {$OverviewTopheads{$_}->{enabled} = $::Options{OPT.'OVTH'.$_};}
		else {$::Options{OPT.'OVTH'.$_} = $OverviewTopheads{$_}->{enabled};}
	}
	
	LoadChart();
}

sub Stop {
	Layout::RegisterWidget(HistoryStats => undef);
}

sub prefbox 
{
	
	my @frame=(Gtk2::Frame->new(" General options "),Gtk2::Frame->new(" History "),Gtk2::Frame->new(" Overview "),Gtk2::Frame->new(" Statistics "));
	
	#General
	my $gAmount1 = ::NewPrefSpinButton(OPT.'CoverSize',50,200, step=>10, page=>25, text =>_("Album cover size"));
	my $gMergeButton = ::NewIconButton('gtk-dialog-warning','Merge fields',\&MergeFields,undef,'Please check README and make sure you understand what this does BEFORE pressing this!');	

	# History
	my $hCheck1 = ::NewPrefCheckButton(OPT.'RequirePlayConditions','Add only songs that count as played', tip => 'You can set treshold for these conditions in Preferences->Misc');
	my $hCheck2 = ::NewPrefCheckButton(OPT.'UseHistoryFilter','Show history only from selected filter');
	my $hCheck3 = ::NewPrefCheckButton(OPT.'LogHistoryToFile','Log playhistory to file');
	my $hAmount = ::NewPrefSpinButton(OPT.'AmountOfHistoryItems',1,1000, step=>1, page=>10, text =>_("Limit history to "));
	my @historylimits = ('items','days');
	my $hCombo = ::NewPrefCombo(OPT.'HistoryLimitMode',\@historylimits);
	my $hEntry1 = ::NewPrefEntry(OPT.'HistoryTimeFormat','Format for time: ', tip => "Available fields are: \%d, \%m, \%y, \%h (12h), \%H (24h), \%M, \%S \%p (am/pm-indicator)");
	my $hEntry2 = ::NewPrefEntry(OPT.'HistoryItemFormat','Format for tracks: ', tip => "You can use all fields from gmusicbrowsers syntax (see http://gmusicbrowser.org/layout_doc.html)");
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
	my @omodes; 
	for (sort keys %timeperiods) { push @omodes, $timeperiods{$_}->{label};}
	my $oCombo = ::NewPrefCombo(OPT.'OverviewTop40Mode',\@omodes, text => 'Update main chart');
	my @omodes2 = ('Artists','Albums','Tracks');
	my $oCombo2 = ::NewPrefCombo(OPT.'OverviewTop40Item',\@omodes2, text => 'Show main chart for ');
	my $oCheck6 = ::NewPrefCheckButton(OPT.'ShowOverviewIcon','Illustrate changes in main chart with icons');
	
	# Statistics
	my $sAmount = ::NewPrefSpinButton(OPT.'AmountOfStatItems',10,10000, step=>5, page=>50, text =>_("Limit amount of shown items to "));
	my $sCheck1 = ::NewPrefCheckButton(OPT.'ShowArtistForAlbumsAndTracks','Show artist for albums and tracks in list');
	my $sCheck4 = ::NewPrefCheckButton(OPT.'PerAlbumInsteadOfTrack','Calculate groupstats per album instead of per track');
	my @sum = (values %statupdatemodes);
	my $sCombo = ::NewPrefCombo(OPT.'StatViewUpdateMode',\@sum, text => 'Update Statistics: ');
	my @randoms;
	push @randoms, $_ for (sort keys %{$::Options{SavedWRandoms}});
	my $sCombo2 = ::NewPrefCombo( OPT.'StatWeightedRandomMode', \@randoms);
	my $sLabel2 = Gtk2::Label->new('Use for weighted random: ');
	my $sCheck8 = ::NewPrefCheckButton(OPT.'WeightedRandomValueType','Show scaled value (0-100) of WRandom-item instead of real');
	my $sLabel1 = Gtk2::Label->new('Show images in list for:');
	$sLabel1->set_alignment(0,0.5);
	my $sCheck9a = ::NewPrefCheckButton(OPT.'StatImageArtist','Artist');
	my $sCheck9b = ::NewPrefCheckButton(OPT.'StatImageAlbum','Album');
	my $sCheck9c = ::NewPrefCheckButton(OPT.'StatImageTitle','Track');
	my $sCheck10 = ::NewPrefCheckButton(OPT.'LastfmStyleHistogram','Show histogram in \'last.fm-style\' (requires restart of plugin)');

	my @vbox = ( 
		::Vpack([$gAmount1,'-',$gMergeButton]), 
		::Vpack([$hCheck1,$hCheck2],[$hCheck3,$hAmount,$hCombo],[$hAmount2,$hAmount3,$hLabel1],[$hEntry1,$hEntry2]), 
		::Vpack($oLabel1,[$oCheck1,$oCheck2,$oCheck3,$oCheck4],[$oAmount,$oAmount2],[$oCombo2,$oCombo],$oCheck6),
		::Vpack([$sCheck1,$sCheck4],[$sCheck10],$sAmount,[$sCombo],[$sLabel2,$sCombo2],$sCheck8,
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
	$self->set_spacing(2);

	my ($Hvbox) = CreateHistorySite($self);
	my ($Ovbox) = CreateOverviewSite($self,$options);	
	my ($Svbox) = CreateStatisticsSite($self);
	my $toolbar = CreateToolbar($self,$options);

	$self->{site_overview} = $Ovbox; 
	$self->{site_history} =  $Hvbox; 
	$self->{site_statistics} = $Svbox;

	my $infobox = Gtk2::HBox->new; 	$infobox->set_spacing(0);
	$infobox->pack_start($Hvbox,1,1,0);
	$infobox->pack_start($Ovbox,1,1,0);
	$infobox->pack_start($Svbox,1,1,0);
	
	#starting site is always 'history'
	# TODO: remember last?
	$Ovbox->set_no_show_all(1);
	$Svbox->set_no_show_all(1);

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
		});
	
	UpdateSite($self,$self->{site});
	return $self;
}

sub CreateHistorySite
{
	my $self = shift;
	
	## TreeView for history
	my $Hstore=Gtk2::ListStore->new('Glib::UInt','Glib::String','Glib::String','Glib::String');
	my $Htreeview=Gtk2::TreeView->new($Hstore);
	my $Hplaytime=Gtk2::TreeViewColumn->new_with_attributes( "Playtime",Gtk2::CellRendererText->new,text => 1);
	$Hplaytime->set_sort_column_id(0);
	$Hplaytime->set_resizable(1);
	$Hplaytime->set_alignment(0);
	$Hplaytime->set_min_width(10);
	my $Htrack=Gtk2::TreeViewColumn->new_with_attributes( _"Track",Gtk2::CellRendererText->new,text=>2);
	$Htrack->set_sort_column_id(1);
	$Htrack->set_expand(1);
	$Htrack->set_resizable(1);
	$Htreeview->append_column($Hplaytime);
	$Htreeview->append_column($Htrack);

	$Htreeview->get_selection->set_mode('multiple');
	$Htreeview->set_rules_hint(1);
	$Htreeview->signal_connect(button_press_event => \&ContextPress);
	my $Hselection = $Htreeview->get_selection;
	$Hselection->signal_connect(changed => \&SelectionChanged);
	$Htreeview->{store}=$Hstore;
	$self->{hstore}=$Hstore;

	my $Hstore_albums=Gtk2::ListStore->new('Glib::UInt','Gtk2::Gdk::Pixbuf','Glib::String','Glib::String','Glib::String');
	my $Htreeview_albums=Gtk2::TreeView->new($Hstore_albums);
	my $Hpic=Gtk2::TreeViewColumn->new_with_attributes( "",Gtk2::CellRendererPixbuf->new,pixbuf => 1);
	$Hpic->set_sort_column_id(0);
	$Hpic->set_resizable(1);
	$Hpic->set_alignment(0);
	$Hpic->set_min_width(10);
	my $Halbum=Gtk2::TreeViewColumn->new_with_attributes( _"Album",Gtk2::CellRendererText->new,text=>2);
	$Halbum->set_sort_column_id(1);
	$Halbum->set_expand(1);
	$Halbum->set_resizable(1);
	my $Hpt=Gtk2::TreeViewColumn->new_with_attributes( _"Playtime",Gtk2::CellRendererText->new,text=>4);
	$Hpt->set_sort_column_id(2);
	$Hpt->set_expand(0);
	$Hpt->set_resizable(1);

	$Htreeview_albums->append_column($Hpic);
	$Htreeview_albums->append_column($Halbum);
	$Htreeview_albums->append_column($Hpt);
	$Htreeview_albums->get_selection->set_mode('multiple');
	$Htreeview_albums->set_rules_hint(1);
	$Htreeview_albums->signal_connect(button_press_event => \&ContextPress);
	my $Hselection_a = $Htreeview_albums->get_selection;
	$Hselection_a->signal_connect(changed => \&SelectionChanged);
	$Htreeview_albums->{store}=$Hstore_albums;
	$self->{hstore_albums}=$Hstore_albums;

	my $vbox = Gtk2::VBox->new;
	$vbox->set_spacing(2);
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

	return ($vbox);
}

sub CreateOverviewSite
{
	my ($self,$options) = @_;
	my $vbox = Gtk2::VBox->new;
	$vbox->set_spacing(2);

	# top-lists
	my @topheads;
	for (sort keys %OverviewTopheads) { push @topheads, $OverviewTopheads{$_}->{label} if $OverviewTopheads{$_}->{enabled};}
	
	my @Ostore_toplists; my @Otoptreeviews; my @Otopselection;
	my $packafter = (($#topheads)%2);
	for (0..$#topheads)
	{
		push @Ostore_toplists, Gtk2::ListStore->new('Glib::UInt','Glib::String','Glib::UInt','Glib::String','Glib::UInt','Glib::String');#ID, label, raw pc, field, max pc, formattedvalue
		push @Otoptreeviews, Gtk2::TreeView->new($Ostore_toplists[$_]);
		
		my $Oitemrenderer=CellRendererLAITE->new;
		my $Oc=Gtk2::TreeViewColumn->new_with_attributes( $topheads[$_],$Oitemrenderer);
		$Oc->set_cell_data_func($Oitemrenderer, sub
		{	my (undef,$cell,$store,$iter)=@_;
			
			my $gid = $store->get($iter,0); my $value = $store->get($iter,2);
			my $max = $store->get($iter,4);
			my %hash = ($gid => $value); my $type = $store->get($iter,3);
			my $psize = 0;#should we enable pics here too?
			my $markup = $store->get($iter,1);
			$cell->set( prop => [$type,$markup,$psize], gid=>$gid, hash => \%hash, max => $max, lastfm => 0);
		});

		
		$Oc->set_expand(1);
		$Otoptreeviews[$_]->append_column($Oc);

		my $Opc=Gtk2::TreeViewColumn->new_with_attributes( "Playcount",Gtk2::CellRendererText->new,text => 5);
		$Opc->set_expand(0);
		$Otoptreeviews[$_]->append_column($Opc);

		$Otoptreeviews[$_]->get_selection->set_mode('multiple');
		$Otoptreeviews[$_]->set_rules_hint(1);
		$Otoptreeviews[$_]->set_headers_visible(1);
		$Otoptreeviews[$_]->signal_connect(button_press_event => \&ContextPress);
		$Otopselection[$_] = $Otoptreeviews[$_]->get_selection;
		$Otopselection[$_]->signal_connect(changed => \&SelectionChanged);
		
		$Otoptreeviews[$_]->{store}=$Ostore_toplists[$_];
		
		
		$Otoptreeviews[$_]->show;
		
		if (($_%2)==$packafter){
			my $hbox = Gtk2::HBox->new; $hbox->set_spacing(2);
			$hbox->pack_start($Otoptreeviews[$_-1],1,1,0) unless (!$_);
			$hbox->pack_start($Otoptreeviews[$_],1,1,0);
			$vbox->pack_start($hbox,0,0,0);
			$hbox->show;
		}
	}
	$self->{ostore_toplist}=\@Ostore_toplists;
	
	
	#treeview for top40
	my $Ostore; my $Otreeview;
	# 0: (g)id, 1: icon, 2: position + lastweek position (if any), 3: field, 4: cover, 5: label, 6: playcount
	$Ostore=Gtk2::ListStore->new('Glib::UInt','Gtk2::Gdk::Pixbuf','Glib::String','Glib::String','Gtk2::Gdk::Pixbuf','Glib::String','Glib::String');

	$Otreeview=Gtk2::TreeView->new($Ostore);
	my $Ocover=Gtk2::TreeViewColumn->new_with_attributes( "",Gtk2::CellRendererPixbuf->new,pixbuf => 4);
	$Ocover->set_sort_column_id(0);
	$Ocover->set_fixed_width($::Options{OPT.'CoverSize'});
	$Ocover->set_min_width($::Options{OPT.'CoverSize'});
	$Ocover->set_expand(0);

	my $Oicon=Gtk2::TreeViewColumn->new_with_attributes( "",Gtk2::CellRendererPixbuf->new,pixbuf => 1);
	$Oicon->set_expand(0);

	my $Olabel=Gtk2::TreeViewColumn->new_with_attributes( "Top ".$::Options{OPT.'OverviewTop40Item'},Gtk2::CellRendererText->new,markup => 5);
	$Olabel->set_sort_column_id(1);
	$Olabel->set_expand(1);
	my $Opc=Gtk2::TreeViewColumn->new_with_attributes( "Playcount",Gtk2::CellRendererText->new,markup => 6);
	$Opc->set_sort_column_id(1);
	$Opc->set_expand(0);
	
	$Otreeview->append_column($Ocover);
	$Otreeview->append_column($Olabel);
	$Otreeview->append_column($Oicon) if ($::Options{OPT.'ShowOverviewIcon'});
	$Otreeview->append_column($Opc);

	$Otreeview->get_selection->set_mode('multiple');
	$Otreeview->set_rules_hint(1);
	$Otreeview->set_headers_visible(1);
	$Otreeview->set_headers_clickable(0);
	$Otreeview->signal_connect(button_press_event => \&ContextPress);
	$Otreeview->signal_connect(map => sub {$Otreeview->get_column(1)->set_title("Top ".$::Options{OPT.'OverviewTop40Item'}.' ('.$::Options{OPT.'OverviewTop40Mode'}.')');});
	my $Oselection = $Otreeview->get_selection;
	$Oselection->signal_connect(changed => \&SelectionChanged);
	$Otreeview->{store}=$Ostore;
	$self->{ostore_main}=$Ostore;

	my $sh = Gtk2::ScrolledWindow->new;
	$sh->add($Otreeview);
	$sh->set_shadow_type('none');
	$sh->set_policy('automatic','automatic');
	$sh->show;
	$vbox->pack_start($sh,1,1,0);
	$Otreeview->show;

	## TreeView for statistics
	my $Ostatstore=Gtk2::ListStore->new('Glib::String','Glib::String','Glib::String');
	my $Ostattreeview=Gtk2::TreeView->new($Ostatstore);
	my $Ostatlabel=Gtk2::TreeViewColumn->new_with_attributes( "Label",Gtk2::CellRendererText->new,text => 0);
	$Ostatlabel->set_sort_column_id(0); $Ostatlabel->set_resizable(1);
	$Ostatlabel->set_expand(1);	$Ostatlabel->set_alignment(0);
	my $Ostattotal=Gtk2::TreeViewColumn->new_with_attributes( _"Total",Gtk2::CellRendererText->new,text=>1);
	$Ostattotal->set_sort_column_id(2); $Ostattotal->set_resizable(1); 
	$Ostattotal->set_expand(0);	$Ostattotal->set_alignment(1);

	$Ostattreeview->append_column($Ostatlabel);
	$Ostattreeview->append_column($Ostattotal);
	$Ostattreeview->get_column(1)->get_cell_renderers()->set_property('xalign',1.0);

	$Ostattreeview->get_selection->set_mode('single');
	$Ostattreeview->set_rules_hint(0);
	$Ostattreeview->set_headers_visible(0);
	$Ostattreeview->{store}=$Ostatstore;
	$self->{ostore_stats}=$Ostatstore;
	$Ostattreeview->show;
	
	$vbox->pack_end($Ostattreeview,0,0,0);

	my $bu = Gtk2::Button->new('Hide');
	$bu->set_alignment(1,.5);
	$bu->signal_connect(clicked => sub 
		{ 
			if ($Ostattreeview->visible){ $Ostattreeview->hide; $bu->set_label('Show');}
			else { $Ostattreeview->show; $bu->set_label('Hide');}
		});
	$bu->show;
	$vbox->pack_end($bu,0,0,0);
	
	#render icons for main chart
	for (keys %OverviewChartIcons){
		$OverviewChartIcons{$_}->{icon} = $self->render_icon($OverviewChartIcons{$_}->{stock},'menu');
	}
	
	return ($vbox,\@Ostore_toplists,$Ostore,$Ostatstore);
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

	my @timeperiodcombonames;
	for (sort keys %timeperiods) { push @timeperiodcombonames, $timeperiods{$_}->{label};}
	my $timeperiodlabel = Gtk2::Label->new('Timeperiod: ');
	my $timeperiodcombo = ::NewPrefCombo(OPT.'TimePeriodCombo',\@timeperiodcombonames);
	$timeperiodcombo->signal_connect(changed => sub {Updatestatistics($self);});
	$timeperiodcombo->show; $timeperiodlabel->show;
	my $stat_hbox2 = Gtk2::HBox->new;
	$stat_hbox2->pack_start($timeperiodlabel,0,0,1);
	$stat_hbox2->pack_start($timeperiodcombo,1,1,1);
	$stat_hbox2->show if ($::Options{OPT.'StatisticsSortCombo'} =~ /Playcount/);
	

	my @combos; my @coptname = (OPT.'StatisticsTypeCombo',OPT.'StatisticsSortCombo');
	for (0..1) {
		$combos[$_] = ::NewPrefCombo($coptname[$_],$lists[$_]);
		if ($_)
		{
			$combos[$_]->signal_connect(changed => sub {
				my $cself = $_[0];
				if (($cself->get_active_text =~ /Playcount/) and (!$stat_hbox2->visible))	{
					$stat_hbox2->show;
				}
				elsif (($cself->get_active_text !~ /Playcount/) and ($stat_hbox2->visible)){
					$stat_hbox2->hide;
				}
				Updatestatistics($self);
			});
		}
		else {$combos[$_]->signal_connect(changed => sub {Updatestatistics($self);});}
		$stat_hbox1->pack_start($labels[$_],0,0,1);
		$stat_hbox1->pack_start($combos[$_],1,1,1);
	}
	$stat_hbox1->show;
	$_->show for (@combos); $_->show for (@labels);
	$self->{stattypecombo} = $combos[1];
	
	#buttons for inv
	my $Sinvert = Gtk2::ToggleButton->new();
	my $iw=Gtk2::Image->new_from_stock('gtk-sort-descending','menu');
	$Sinvert->add($iw);
	$Sinvert->set_tooltip_text('Invert sorting order');
	$Sinvert->signal_connect(toggled => sub {Updatestatistics($self);});
	$Sinvert->show; $iw->show;
	$self->{butinvert} = $Sinvert;
	
	
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
			$cell->set( prop => [$type,$markup,$psize], gid=>$gid, hash => \%hash, max => $max, lastfm => $::Options{OPT.'LastfmStyleHistogram'});
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
			
			my $bg = ($::Options{OPT.'LastfmStyleHistogram'})? $self->style->base('normal') : undef;
			$cell->set( prop => [$type,$markup,$psize], gid=>$gid, hash => \%hash, max => $max, cell_background_gdk => $bg, nopic => 1, lastfm => $::Options{OPT.'LastfmStyleHistogram'});
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
	$Sselection->signal_connect(changed => \&SelectionChanged);
	
	$Streeview->signal_connect(button_press_event => \&ContextPress);
	$Streeview->{store}=$Sstore;
	$self->{sstore}=$Sstore;
	$Streeview->show;
	
	my $sh = Gtk2::ScrolledWindow->new;
	$sh->add($Streeview);
	$sh->set_shadow_type('none');
	$sh->set_policy('automatic','automatic');
	$sh->show;
	
	my $Svbox = Gtk2::VBox->new(); 
	$Svbox->pack_start($stat_hbox1,0,0,0);
	$Svbox->pack_start($stat_hbox2,0,0,0);
	$Svbox->pack_start($sh,1,1,0);
	
	return ($Svbox);	
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
	
	if (($sorttype eq 'playcount') and ($::Options{OPT.'TimePeriodCombo'} ne 'Overall')) { # timeperiodic
		($dh) = CalcTimePeriodCount($field,$source,$suffix);
	} 
	elsif (($field !~ /album|title/) and ($::Options{OPT.'PerAlbumInsteadOfTrack'}) and ($suffix eq ':average') and ($sorttype ne 'weighted')) { # album-based average
		($dh) = CalcAlbumBasedAverage($field,$source,$sorttype);
	}
	elsif ($sorttype eq 'weighted'){ # wRandom
			my $randommode = Random->new(${$::Options{SavedWRandoms}}{$::Options{OPT.'StatWeightedRandomMode'}},$source);
			my $sub = ($field eq 'title')? $randommode->MakeSingleScoreFunction() : $randommode->MakeGroupScoreFunction($field);
			($dh)=$sub->($source);
			ScaleWRandom(\%$dh,$field);
	}
	else { ($dh) = Songs::BuildHash(($field eq 'title')? 'id':$field, $source, undef, $sorttype.$suffix); } # 'normal mode'

	return unless (scalar keys %$dh);
	
	#we got values, send 'em up!
	$max = ($::Options{OPT.'AmountOfStatItems'} < (scalar keys %$dh))? $::Options{OPT.'AmountOfStatItems'} : (scalar keys %$dh);
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
			$$dh{$ci} = 0 unless (defined $$dh{$ci});
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

	# general statistics
	$self->{ostore_stats}->clear;
	my $statref = CalcStatus();
	
	for (sort keys %$statref)
	{
		$self->{ostore_stats}->set($self->{ostore_stats}->append,
			0,$$statref{$_}->{label},
			1,$$statref{$_}->{value},
		);
	}

	#toplists
	$_->clear for (@{$self->{ostore_toplist}});
	my @topheads; 
	for (sort keys %OverviewTopheads) { push @topheads, $_ if ($OverviewTopheads{$_}->{enabled});};
	my $numberofitems;
	
	for my $store (0..$#topheads)
	{
		my $topref; my $smode = ($::Options{OPT.'OverviewTopMode'}); $smode =~ s/\:(.+)//;
		if ($topheads[$store] eq 'title')
		{
			my $lr = $::Library;
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
		my $maxvalue;
		for my $row (0..($numberofitems-1))
		{
			my $title; my $value;
			if ($topheads[$store] eq 'title') {
				($title,$value) = Songs::Get($list[$row],'title',$smode);
			}
			else {
				$title = Songs::Gid_to_Display($topheads[$store],$list[$row]);
				$value = $$topref{$list[$row]};
			}
			$maxvalue = $value unless ($maxvalue);

			#ID, label, raw pc, field, max pc, formattedvalue
			${$self->{ostore_toplist}}[$store]->set(${$self->{ostore_toplist}}[$store]->append,
					0,$list[$row],
					1,$title,
					2,$value,
					3,$topheads[$store],
					4,$maxvalue,
					5,::__('%d play','%d plays',$value)
					);
		}
	}
	
	
	# Main Chart

	my %fc = (Artists => 'artist', Albums => 'album', Tracks => 'id');
	my $dh; my $max; my $field = $fc{$::Options{OPT.'OverviewTop40Item'}} || 'album';
	my $pcs; my $oldpcs;

	my ($starttime,$endtime,$timeperiod) = GetTimeSpan($::Options{OPT.'OverviewTop40Mode'});

	if ($endtime){$pcs = Songs::BuildHash($field,$::Library,undef,'playhistory:countrange:'.$starttime.'-'.$endtime);}
	else {$pcs = Songs::BuildHash($field,$::Library,undef,'playhistory:countafter:'.$starttime);}

	my @oldmainchart_list;
	if (($timeperiod) and ($::Options{OPT.'ShowOverviewHistory'})){
		$oldpcs = Songs::BuildHash($field,$::Library,undef,'playhistory:countrange:'.($starttime-$timeperiod).'-'.($starttime-1));
		my $oldmax = ($::Options{OPT.'OverviewTop40Amount'} < (scalar keys %$oldpcs))? ($::Options{OPT.'OverviewTop40Amount'}) : (scalar keys %$oldpcs);
		@oldmainchart_list = (sort { $$oldpcs{$b} <=> $$oldpcs{$a}} keys %{$oldpcs})[0..($oldmax-1)];
	}
	
	$max = ($::Options{OPT.'OverviewTop40Amount'} < (scalar keys %$pcs))? $::Options{OPT.'OverviewTop40Amount'} : (scalar keys %$pcs);
	my @mainchart_list = (sort { $$pcs{$b} <=> $$pcs{$a}} keys %{$pcs})[0..($max-1)];

	$self->{ostore_main}->clear;
	
	for my $listkey (0..$#mainchart_list){
		my $icon;
		my $pic; 
		my $label = HandleStatMarkup($field,$mainchart_list[$listkey],($listkey+1).'. ',::TRUE,::TRUE);
		my $value = ::__('%s play','%s plays',$$pcs{$mainchart_list[$listkey]});
		
		if (defined $$oldpcs{$mainchart_list[$listkey]}){
			my ($num) = grep { $mainchart_list[$listkey] == $oldmainchart_list[$_] } 0..$#oldmainchart_list;
			
			$value .= "\n<small>".::__('%s play','%s plays',$$oldpcs{$mainchart_list[$listkey]}).((defined $num)? ' ('.($num+1).'.)' : '').' </small>';
			
			if ($::Options{OPT.'ShowOverviewIcon'}){
				if ((defined $num) and ($num < $listkey)) {$icon = $OverviewChartIcons{down}->{icon};}
				elsif ((defined $num) and ($num == $listkey)) {$icon = $OverviewChartIcons{same}->{icon};}
				elsif ((defined $num) and ($num > $listkey)) {$icon = $OverviewChartIcons{up}->{icon};}
			}
		}
		
		if (($::Options{OPT.'ShowOverviewIcon'}) and (not defined $icon)) 
		{
			#item wasn't played in previous ('old') timeperiod, but might have been played before
			# we only want to check whether it has been on a list the user has seen, so we don't care about it's 'true history'
			if (HasBeenInChart($field,$mainchart_list[$listkey],($starttime-$timeperiod))) {$icon = $OverviewChartIcons{reappear}->{icon};}
			else {$icon = $OverviewChartIcons{first}->{icon};}
		}

		if ($field eq 'id'){
			$label = ::ReplaceFields($mainchart_list[$listkey],$label,::TRUE );
			$pic = AAPicture::pixbuf('album', Songs::Get_gid($mainchart_list[$listkey],'album'), $::Options{OPT.'CoverSize'}, 1);	
			if (!$pic){ $pic = $self->render_icon("gmb-song","large-toolbar");}
		}
		else{
			$label = AA::ReplaceFields($mainchart_list[$listkey],$label,$field,::TRUE );
			$pic = AAPicture::pixbuf($field, $mainchart_list[$listkey], $::Options{OPT.'CoverSize'}, 1);
			if (!$pic){ $pic = $self->render_icon("gmb-".$field,"large-toolbar");}
		}
		$self->{ostore_main}->set($self->{ostore_main}->append,
			0,$mainchart_list[$listkey],
			1,$icon,
			2,$listkey,
			3,$field,
			4,$pic,
			5,$label,
			6,$value,
		);
		
		$ChartHistory{$field}->{$mainchart_list[$listkey]} = time unless (defined $ChartHistory{$field}->{$mainchart_list[$listkey]});
	}
	
	SaveChart();
	
	return 1;
}

sub Updatehistory
{
	my $self = shift;
	
	my $source = (($::Options{OPT.'UseHistoryFilter'}) and (defined $::SelectedFilter))? $::SelectedFilter->filter : $::Library;
	my $h = Songs::BuildHash('id', $source, undef, 'playhistory');
	my %hHash;
	
	for my $hashistory (keys %$h) {	# hashistory are every song in library that has playhistory
		for my $plt (keys $$h{$hashistory}){ # plt are playtimes (epoch) 
			$hHash{$plt} = $hashistory;
		}
	}
	
	my $lasttime = 0; my $amount=0;
	if ($::Options{OPT.'HistoryLimitMode'} eq 'days') {
		$lasttime = time-(($::Options{OPT.'AmountOfHistoryItems'}-1)*86400);
		my ($sec, $min, $hour) = (localtime(time))[0,1,2];
		$lasttime -= ($sec+(60*$min)+(3600*$hour));
		my $hh = Songs::BuildHash('album_artist', $source, undef, 'playhistory:countafter:'.$lasttime);
		for (keys %$hh) { $amount += $$hh{$_}; }; #could this be done more easily?
	}
	else { $amount = ((scalar keys(%hHash)) < $::Options{OPT.'AmountOfHistoryItems'})? scalar keys(%hHash) : $::Options{OPT.'AmountOfHistoryItems'}; }
	
	my %seen_alb; my %albumplaytimes; my @albumorder;

	$self->{hstore}->clear;
	
	for my $key ((sort { $b <=> $a } keys %hHash)[0..($amount-1)]) 
	{
		#take note for albums
		my $album_gid = Songs::Get_gid($hHash{$key},'album');
		
		push @{$seen_alb{$album_gid}}, $hHash{$key};
		unless (defined $albumplaytimes{$album_gid})
		{
			$albumplaytimes{$album_gid} = $key;
			push @albumorder,$album_gid;
		}

		#add to store
		$self->{hstore}->set($self->{hstore}->append,
				0,$hHash{$key},
				1,FormatRealtime($key),
				2,::ReplaceFields($hHash{$key},$::Options{OPT.'HistoryItemFormat'} || '%a - %l - %t'),
				3,'title');

		last unless ($key > $lasttime);
		last if (defined $amount) and (--$amount <= 0);
	}
	
	# Albums' history
	
	my @real_source; my @playedsongs;
	for my $key (@albumorder) {
		push @real_source, @{AA::Get('id:list','album',$key)};
		push @playedsongs, @{$seen_alb{$key}};
	}
	my ($totallengths) = Songs::BuildHash('album', \@real_source, undef, 'length:sum');
	my ($playedlengths) = Songs::BuildHash('album', \@playedsongs, undef, 'length:sum');

	$self->{hstore_albums}->clear;

	for my $key (@albumorder) 
	{
		#don't add album if treshold doesn't hold
		next unless ((($$playedlengths{$key}*100)/$$totallengths{$key} > $::Options{OPT.'HistAlbumPlayedPerc'}) or (($$playedlengths{$key}/60) > $::Options{OPT.'HistAlbumPlayedMin'}));

		my $xref = AA::Get('album_artist:gid','album',$key);
		$self->{hstore_albums}->set($self->{hstore_albums}->append,
			0,$key,
			1,AAPicture::pixbuf('album', $key, $::Options{OPT.'CoverSize'}, 1),
			2,Songs::Gid_to_Display('album',$key)."\n by ".Songs::Gid_to_Display('artist',$$xref[0]),
			3,'album',
			4,FormatRealtime($albumplaytimes{$key})
			);
	}	
	
	return 1;	 
}

sub FormatSmalltime
{
	my $sec = shift;

	my $result = '';
	
	if ($sec > 31536000) { $result .= int($sec/31536000).'y '; $sec = $sec%31536000;}
	if ($sec > 2592000) { $result .= int($sec/2592000).'m '; $sec = $sec%2592000; }
	elsif ($sec > 604800) { $result .= int($sec/604800).'wk '; $sec = $sec%604800;} #show either weeks or months, not both
	if ($sec > 86400) { $result .= int($sec/86400).'d '; $sec = $sec%86400;}
	if ($sec > 3600) { $result .= sprintf("%02d",int($sec/3600)).':'; $sec = $sec%3600;}
	$result .= sprintf("%02d",int($sec/60)).':'.sprintf("%02d",int($sec%60));

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

sub GetTimeSpan
{
	my $label = shift;
	
	my ($span) = grep { $timeperiods{$_}->{label} eq $label} keys %timeperiods;
	$span = $timeperiods{$span}->{dayspan};
	
	return (undef,undef,undef) unless (defined $span);
	
	my $starttime; my $endtime; my $timeperiod;
	
	if ($span =~ /^(\d+)$/) { 
		$timeperiod = $span*86400; 
		$starttime = time-$timeperiod;
		$endtime = 0;
	}
	else{
		if ($span eq 'o') { $timeperiod = 0; $starttime = 0; $endtime = time;}
		elsif ($span eq 'w') { 
			$timeperiod = 7*86400;
			my ($s,$m,$h,$wday) = ( localtime time )[0,1,2,6];
			$starttime = time - ((7 + (($wday == 0)? 6 : ($wday-1))) * 86400);
			$starttime -= ($h*3600+$m*60+$s);
			$endtime = $starttime+$timeperiod;
		}
		elsif ($span eq 'm') { 
			my ($m,$y) = ( localtime time )[4,5];
			$starttime = ::mktime( 0, 0, 0, 1, $m - 1, $y );
			$endtime = ::mktime( 0, 0, 0, 1, $m, $y );  
			$timeperiod = $starttime - ::mktime( 0, 0, 0, 1, $m - 2, $y );
		}
	}
	
	return ($starttime,$endtime,$timeperiod);
}

sub CalcTimePeriodCount
{
	my ($field,$source,$suffix) = @_;
	my $dh;
	my ($starttime,$endtime,$timeperiod) = GetTimeSpan($::Options{OPT.'TimePeriodCombo'});
	if ($endtime){($dh) = Songs::BuildHash(($field eq 'title')? 'id':$field,$source,undef,'playhistory:countrange:'.$starttime.'-'.$endtime);}
	else {($dh) = Songs::BuildHash(($field eq 'title')? 'id':$field,$source,undef,'playhistory:countafter:'.$starttime);}

	if (($field !~ /album|title/) and ($::Options{OPT.'PerAlbumInsteadOfTrack'}) and ($suffix =~ /average/)) # album-based  
	{
		my ($ah);
		if ($endtime){($ah) = Songs::BuildHash('album',$source,undef,'playhistory:countrange:'.$starttime.'-'.$endtime);}
		else {($ah) = Songs::BuildHash('album',$source,undef,'playhistory:countafter:'.$starttime);}
		
		for (keys %$ah) { 
			my $aalist = AA::Get('id:list','album',$_);
			next unless ((defined $aalist) and (scalar@$aalist));
			$$ah{$_} /= scalar@$aalist;
		}

		$dh = CalcAlbumBasedAverage($field,$source,'playcount',$dh,$ah);

	}
	elsif (($suffix =~ /average/) and ($field !~ /^title$/))
	{
		for (keys %$dh)
		{
			my $alist = AA::Get('id:list',$field,$_);
			next unless ((defined $alist) and (scalar@$alist));
			$$dh{$_} /= scalar@$alist;
		}
	}
	
	return $dh;
}
sub CalcAlbumBasedAverage
{
	my ($field,$source,$sorttype,$dh,$ah) = @_;
	
	unless ((defined $dh) and (defined $ah))
	{
		($dh) = Songs::BuildHash($field, $source, undef, $sorttype.':sum');
		($ah) = Songs::BuildHash('album', $source, undef, $sorttype.':average');
	}
	
	for my $gid (keys %$dh) {
		my $albums = AA::Get('album:gid',$field,$gid);
		next unless (scalar@$albums);
		$$dh{$gid} = 0;
		my $ok=0;
		for (@$albums) {
			my $ilist = AA::Get($field.':gid','album',$_);
			next unless ((ref($ilist) ne 'ARRAY') or ((scalar@$ilist == 1) and ($$ilist[0] == $gid)));
			$$dh{$gid} += $$ah{$_} if (defined $$ah{$_});
			$ok++;
		}
		$$dh{$gid} /= $ok unless (!$ok);
	}

	return $dh;	
}
sub HandleStatMarkup
{
	my ($field,$id,$listnum,$HasPic,$wantSmall) = @_;
	$listnum = '' unless (defined $listnum);
	$field = 'title' if ($field eq 'id');
	$wantSmall = 0 unless (defined $wantSmall);
	my $markup = ($field eq 'title')? $listnum."%t": $listnum."%a";	
	
	if ($::SongID){
		my $nowplaying = ($field eq 'title')? $::SongID : Songs::Get_gid($::SongID,$field);
		if (ref($nowplaying) eq 'ARRAY') { for (@$nowplaying) {if ($_ == $id) {$markup = '<b>'.$markup.'</b>';}}}
		elsif ($nowplaying == $id) { $markup = '<b>'.$markup.'</b>';}
	}

	if (($::Options{OPT.'ShowArtistForAlbumsAndTracks'}) and ($field =~ /album|title/))
	{
		unless (defined $HasPic) {$HasPic = ($::Options{'PLUGIN_HISTORYSTATS_StatImage'.ucfirst($field)})? 1 : 0;}
		if ($field eq 'album') {
			if ($HasPic) {
				if ($wantSmall) {$markup = $markup."\n\t <small>by ".::PangoEsc(Songs::Gid_to_Display('artist',@{AA::Get('album_artist:gid','album',$id)}[0]))."</small>";}
				else  {$markup = $markup."\n\t by ".::PangoEsc(Songs::Gid_to_Display('artist',@{AA::Get('album_artist:gid','album',$id)}[0]));}
			}
			else {$markup = $markup."<small>  by  ".::PangoEsc(Songs::Gid_to_Display('artist',@{AA::Get('album_artist:gid','album',$id)}[0])).'</small>';}
		}
		elsif ($field eq 'title'){
			if ($HasPic) { $markup = $markup."\n\t by %a";}
			else {$markup = $markup."<small> by %a </small>"}
		}
	}
	
	return $markup;
}

sub ContextPress
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
		if ($field !~ /^title$|^id$/){
			if (scalar@IDs == 1) {::PopupAAContextMenu({gid=>$IDs[0],self=>$treeview,field=>$field,mode=>'S'});}
			else {
				my @idlist;
				for (@IDs) {push @idlist , @{AA::Get('id:list',$field,$_)};}
				::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $treeview, IDs => \@idlist});
			}
		}
		else {
			::PopupContextMenu(\@::SongCMenu,{mode=> 'S', self=> $treeview, IDs => \@IDs});
		}
	}
	elsif (($event->button == 1) and ($event->type  eq '2button-press') and (scalar@IDs == 1)) {
		if ($field !~ /^title$|^id$/){
			my $aalist = AA::Get('id:list',$field,$IDs[0]);
			Songs::SortList($aalist,$::Options{Sort} || $::Options{Sort_LastOrdered});
			::Select( filter => Songs::MakeFilterFromGID($field,$IDs[0])) if ($::Options{OPT.'FilterOnDblClick'});
			::Select( song => $$aalist[0], play => 1);
		}
		else { ::Select(song => $IDs[0], play => 1);}
	}
	else { return 0;}
	
	return 1;
}

sub SelectionChanged
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
		next if ($field =~ /^title$|^id$/);
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
	elsif (($self->{site} eq 'overview') and ($albumhaschanged)) {$force = 1;}
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

	return 1;
}

sub AddToHistory
{
	my ($self,$ID,$playtime) = @_;	

	$lastAdded{ID} = $ID;
	$lastAdded{playtime} = $playtime;

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

sub SaveChart
{
	return 'no ChartFile' unless defined $ChartFile;

	my $content='ChartHistory v.'.$VNUM."\n";

	for my $field (keys %ChartHistory)
	{
		$content .= "[".$field."]\n";
		for my $item (keys %{$ChartHistory{$field}})
		{
			my $label = ($field eq 'title')? Songs::Get($item,'title') : Songs::Gid_to_Display($field,$item);
			$content .= $item."\t".$label."\t".$ChartHistory{$field}->{$item}."\n";
		}
	}

	open my $fh,'>',$ChartFile or warn "Error opening '$ChartFile' for writing : $!\n";
	print $fh $content or warn "Error writing to '$ChartFile' : $!\n";
	close $fh;
	
	return 1;	
}
sub LoadChart
{
	return 0 unless defined $ChartFile;
	my $read=0;
	
	open my $fh,'<',$ChartFile or return 0;
	my @lines = <$fh>;
	close($fh);
	
	my $header = shift @lines;
	return 0 unless ($header =~ /ChartHistory v\.(\d+)(\.\d+)?$/);
	my $field;
	for my $line (@lines)
	{
		if ($line =~ /^\[(.+)\]$/) {$field = $1; next;}
		next unless (defined $field);
		next unless ($line =~ /^(\d+)\t(.+)\t(\d+)$/);
		my $item = $1; my $check = $2; my $playtime = $3;
		my $wantedlabel = ($field eq 'title')? Songs::Get($item,'title') : Songs::Gid_to_Display($field,$item);
		next unless ($wantedlabel eq $check);
		$ChartHistory{$field}->{$item} = $playtime;
		$read++;
	}

	return 1;
}
sub HasBeenInChart
{
	my ($field,$ID,$starttime) = @_;

	return 1 if ((defined $ChartHistory{$field}->{$ID}) and ($ChartHistory{$field}->{$ID} < $starttime));
		
	return 0;
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

sub CalcStatus
{
	my $self = shift;
	my %statustexts;

	my $ago = int(100*((time-$globalstats{starttime})/86400));
	$ago /= 100;
	
	$statustexts{1}->{label} = "Statistics started"; 
	$statustexts{1}->{value} = FormatRealtime($globalstats{starttime},'%d.%m.%y')." (".$ago." days ago)";

	return \%statustexts unless ($ago);
	
	$statustexts{2}->{label} = "Tracks Played";
	$statustexts{2}->{value} = $globalstats{playtrack}." (".sprintf ("%.2f", $globalstats{playtrack}/$ago)." per day)";

	$statustexts{3}->{label} = "Time Played";
	$statustexts{3}->{value} = FormatSmalltime($globalstats{playtime})." (".FormatSmalltime($globalstats{playtime}/$ago)." per day)";
	
	return \%statustexts;
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

sub ConfirmMerging
{
	my $dialog = Gtk2::MessageDialog->new( undef, [qw/modal destroy-with-parent/], 'warning','ok-cancel','This will modify your filetags permanently. Do you still want to continue?' );
	$dialog->set_position('center-always');
	$dialog->set_default_response ('cancel');
	$dialog->set_title('History/Stats confirmation');
	$dialog->show_all;

	my $response = $dialog->run;
	$dialog->destroy;
	return $response;
}

sub MergeFields
{
	return if ($merging);
	return unless (ConfirmMerging() eq 'ok');

	$merging = 1;
	my ($dh) = Songs::BuildHash('id', $::Library, undef, 'lastplay');
	my %foundkeys;
	for my $ID (keys %$dh) {
		my $playtime = (keys %{$$dh{$ID}})[0];
		next unless ($playtime);
		$foundkeys{$ID} = $playtime;
	}

	warn "Found ".(scalar keys %foundkeys)." items with 'lastplay'";
	warn "Now setting data to playhistory (no backsies!)";
	
	my $abort; my $i=0;
	my $pid= ::Progress( undef, end=>scalar(keys %foundkeys), abortcb=>sub {$abort=1}, title=>_"Merging data");
	Glib::Idle->add(sub
	{	
		my $ID= (keys %foundkeys)[$i];
		if (defined $ID){ Songs::Set($ID,'+playhistory' => $foundkeys{$ID});	}
		$i++;
		if ($abort || $i>=(scalar keys %foundkeys))
		{	::Progress($pid, abort=>1);
			$merging = 0;
			return 0;
		}
		::Progress( $pid, current=>$i );
		return 1;
	 });		
	
	return 1;
}

package CellRendererLAITE;
use Glib::Object::Subclass 'Gtk2::CellRenderer',
properties => [ Glib::ParamSpec->ulong('gid', 'gid', 'group id',		0, 2**32-1, 0,	[qw/readable writable/]),
		Glib::ParamSpec->boolean('nopic', 'nopic', 'nopic',	0, [qw/readable writable/]),
		Glib::ParamSpec->boolean('lastfm', 'lastfm', 'last.fm style',	0, [qw/readable writable/]),
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
	my ($prop,$gid,$hash,$max,$nopic,$lastfm)=$cell->get(qw/prop gid hash max nopic lastfm/);
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
	if ($max)
	{	
		my $maxwidth = ($background_area->width) - XPAD;
		$maxwidth-= $psize unless ($nopic);
		$maxwidth=5 if $maxwidth<5;

		my $width= ((100*$hash->{$gid}) / $max) * $maxwidth / 100;
		$width = ($hash->{$gid})? ::max($width,int($maxwidth/5)) : 0;
		
		$startx = ($lastfm)? $cell_area->x : $x+$psize+XPAD;
		$lstate = 'selected' if ($lastfm);
		if ($width){
			$widget->style->paint_flat_box( $window,$lstate,'none',$expose_area,$widget,'',
				$startx, $cell_area->y, $width, $cell_area->height );
		}
	}
	elsif (($lastfm) and ($ICanHasPic) and (!$nopic)){ $startx = $x+$psize+XPAD;}
	else {$startx = $cell_area->x;}
	
	$startx = $startx+PAD+XPAD;
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