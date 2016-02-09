package pubmedBatch;

use strict;
use warnings;
use 5.16.0;
use File::Spec;
use Dancer2;
use JSON;
use POSIX qw(strftime);
use Template;
use Dancer2::Plugin::ProgressStatus;
use Bio::DB::EUtilities;
use XML::LibXML;
use Text::CSV;
use File::Path qw(make_path);
use Try::Tiny;

our $VERSION = '0.1';

##################
# Route handler  #
##################

hook before_template => sub {
    # Defining some commonly used urls in the templates.
    my $tokens = shift;
    
    $tokens->{'css_url'} = request->base . 'css/style.css';
    $tokens->{'main_css'} = request->base. 'css/main.css';
    $tokens->{'main_js'} = request->base. 'javascripts/main.js';
    $tokens->{'d3_js'} = request->base. 'javascripts/d3.min.js';
    $tokens->{'j_dragtable'} = request->base. 'javascripts/jquery.dragtable.js';
    $tokens->{'j_tablesorter'} = request->base. 'javascripts/jquery.tablesorter.js';
    #$tokens->{'bootstrap_css'} = request->base. 'css/bootstrap.min.css';
    $tokens->{'bootstrap_css'} = '//maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.min.css';
    #$tokens->{'bootstrap_js'} = request->base. 'javascripts/bootstrap.min.js';
    $tokens->{'bootstrap_js'} = '//maxcdn.bootstrapcdn.com/bootstrap/3.3.6/js/bootstrap.min.js';
    $tokens->{'jquery'} = 'https://code.jquery.com/jquery-2.2.0.min.js';
    #$tokens->{'jquery'} = request->base. 'javascripts/jquery.min.js';
    $tokens->{'jquery_ui'} = request->base. 'javascripts/jquery-ui.min.js';
};

any ['get', 'post'] => '/batch_pubmed/:user' => sub {
    # user id decides where the JSON files are saved.
    my $user = params->{user};
    
    # the massive hugo term + pubmed search
    if (request->method() eq 'POST'){
        # request has been made. let's deal with it.
        # ajax query to get the data
        my $prog 	= start_progress_status({name => 'progress'});
        my %tokens 	= params;
        my $verbose = $tokens{verbose} ? 1 : 0; # control if pull out all results, instead of results with total pubmed score > 0
        
        my $csv_file 	= upload('csv_upload');
        my $known_genes = $tokens{'known_genes'} ? upload('known_genes') : '';
        my $mask_genes	= $tokens{'mask_genes'} ? upload('mask_genes') : '';
        #make a filename to store the resulting JSON structure, yyyy_mm_dd_filename.json
        my $now 		= strftime "%Y_%m_%d", localtime;
        my $file_name 	= $now.'_'.(substr $tokens{csv_upload}, 0, -4).'.json';
        
        $csv_file 		= $csv_file->content;
        $known_genes	= $known_genes ? $known_genes->content : '';
        $mask_genes		= $mask_genes ? $mask_genes->content : '';
        if ( is_progress_running('progress') ) {
            return 'Progress is already running, please wait until it finishes';
        }
        # how many lines?
        my $lines = () = ($csv_file =~ /(\n)/g);
        # initiate the progress bar
        $prog->{total} = $lines;
        
        # translate terms
        my @or = split ' ', $tokens{OR};
        my @and = split ' ', $tokens{AND};
        my @field_or = map {q(").$_.q(").q([All Fields])} @or;
        my @field_and = map {q(").$_.q(").q([Title/Abstract])} @and;
        my $smashed_or = join ' OR ', @field_or;
        my $smashed_and = join ' AND ', @field_and;
        my $smashed_terms = ' AND ('.$smashed_or.')';
        if ($tokens{AND}){
            $smashed_terms .= ' AND '.$smashed_and;
        }
        my $col_num = $tokens{column};
        # grep the header
        my ($header_line) = ($csv_file =~ /^(.*)?\n/);
        $header_line =~ s/"//g; #get rid of "
        my @header = split ',', $header_line;
        
        # add another 2 column right after HUGO
        splice @header, $col_num + 1, 0, ('ref(pubmedID)', 'pubmed_score');
        # and add a Pred score column at the beginning
        unshift @header, 'pred_score';
        
        
        #################################################################################
        # Now's the real deal
        #################################################################################
        my $csv = Text::CSV->new({ binary => 1, eol => $/ });
        my $row = -1;
        my %genes;
        my @output;
        while ($csv_file =~ /^(.*?\n)/mg){
            # parse line. skip first line.
            $row++;
            $row or next;
            my $status = $csv->parse($1);
            $status and my @fields = $csv->fields();
            my $gene_name = $fields[$col_num];
            #update progress;
            $prog++;
            # getting gene name
            next if $gene_name eq 'NA';
            # get rid of all parentheses and their content
            $gene_name =~ s/\([^)]*\)?//;
            
            if(exists $genes{$gene_name}){
                # already queried, no need to wait.
                warn $gene_name;
                unless ($verbose or $genes{$gene_name}->{total_score}){
                    # jump to next record if total score is 0
                    next ;
                }
                
                splice @fields, $col_num + 1, 0, ($genes{$gene_name}, $genes{$gene_name}->{total_score});
                # add a placeholder for pred_score
                unshift @fields, 0;
                my $ha;
                for my $col (0..$#header){
                    $ha->{$header[$col]} = $fields[$col];
                }
                
                # get pred score.
                my $pred = get_pred_score($ha);
                
                # pred score > cutoff?
                next unless ($verbose or $pred >= $tokens{pred});
                
                $ha->{pred_score} = $pred;
                push @output, $ha;
            } elsif($mask_genes =~ /\b$gene_name\b/){
                # masked, skip calculation
                $genes{$gene_name} = {total_score => 0, results => ['masked']};
                next unless $verbose;
                splice @fields, $col_num + 1, 0, ($genes{$gene_name}, 0);
                # add a placeholder for pred_score
                unshift @fields, 0;
                my $ha;
                for my $col (0..$#header){
                    $ha->{$header[$col]} = $fields[$col];
                }
                $ha->{pred_score} = get_pred_score($ha);
                push @output, $ha;
            } else {
                my $eutil;
                # ncbi might not respond. this will throw an error. catch and repeat it after 5 sec
                
                $eutil = Bio::DB::EUtilities->new(
                -eutil      => 'esearch',
                -term       => $gene_name.$smashed_terms,
                -db         => 'pubmed',
                -retmax     => 1000,
                -email      => $tokens{email},
                );
                
                my $err = 1;
                my @ids;
                while($err) {
                    try {
                        @ids = $eutil->get_ids;
                        $err = 0;
                    } catch {
                        my $error = shift;
                        warn $error;
                        warn "sleep for 5 sec";
                        sleep(5);
                    };
                }
                
                if (@ids){
                    # has a positive hit. Change the first cell in the row to be 'bold'
                    # first to check all the ids for validity
                    my $results = scrutinise(ids =>\@ids, terms => \@or, email => $tokens{email});
                    # populate %genes and %output
                    $genes{$gene_name} = $results;
                    
                    # known genes?
                    $genes{$gene_name}->{known} =  ($known_genes =~ /\b$gene_name\b/) ? 1 : 0;
                    
                    unless ($verbose or $genes{$gene_name}->{total_score}){
                        # jump to next record if total score is 0
                        next ;
                    }
                    splice @fields, $col_num + 1, 0, ($genes{$gene_name}, $genes{$gene_name}->{total_score});
                    # add a placeholder for pred_score
                    unshift @fields, 0;
                    my $ha;
                    for my $col (0..$#header){
                        $ha->{$header[$col]} = $fields[$col];
                    }
                    # get pred score.
                    my $pred = get_pred_score($ha);
                    
                    # pred score > cutoff?
                    next unless ($verbose or $pred >= $tokens{pred});
                    
                    $ha->{pred_score} = $pred;
                    push @output, $ha;
                } else {
                    # nothing exciting, just write
                    
                    # verbose?
                    next unless $verbose;
                    
                    $genes{$gene_name} = {total_score => 0, results => []};
                    
                    # known genes?
                    $genes{$gene_name}->{known} = ($known_genes =~ /\b$gene_name\b/) ? 1 : 0;
                    
                    splice @fields, $col_num + 1, 0, ($genes{$gene_name}, $genes{$gene_name}->{total_score});
                    # add a placeholder for pred_score
                    unshift @fields, 0;
                    my $ha;
                    for my $col (0..$#header){
                        $ha->{$header[$col]} = $fields[$col];
                    }
                    # get pred score.
                    my $pred = get_pred_score($ha);
                    
                    # pred score > cutoff?
                    next unless ($verbose or $pred >= $tokens{pred});
                    
                    $ha->{pred_score} = $pred;
                    push @output, $ha;
                }
                # seems there's a limit on how many (3) searhces can be done per second, so sleep for a little while
                sleep(0.4);
            }
            
            #update progress;
            $prog->add_message("$row $gene_name score: ".$genes{$gene_name}->{total_score}) if $genes{$gene_name}->{total_score};
        }
        
        my $result = to_json([\@header, \@output]);
        
        #logged in? can save result
        if ($user){
            # write result to $file_name
            # make path and file_name
            my $data_path = File::Spec->catdir('batch_pubmed_result',$user);
            make_path($data_path, {verbose => 1});
            $file_name = File::Spec->catfile($data_path, $file_name);
            
            # write and win
            open my $fh, '>', $file_name;
            binmode $fh, ":encoding(UTF-8)";
            print $fh $result;
        }
        return $result;
    } else {
        # this is the get content
        
        # get saved content
        my @saved_data;
        if ($user){
            # write result to $file_name
            # make path and file_name
            my $data_path = File::Spec->catdir('batch_pubmed_result',$user);
            opendir(my $dir, $data_path);
            @saved_data = readdir $dir;
            @saved_data = map { substr $_, 0, -5 } grep { /json$/ } @saved_data;
        }
        @saved_data = sort @saved_data;
        template 'tools_batch_pubmed.tt', {
            user        => $user,
            saved_data  => \@saved_data,
        };
    }
};

post '/batch_pubmed/:user/:file' => sub {
    # fetch saved data
    my $user = params->{user};
    my $file_name = params->{file}.'.json';
    $file_name = File::Spec->catfile('batch_pubmed_result', $user, $file_name);
    open my $fh, '<:encoding(UTF-8)', $file_name;
    return <$fh>;
};

post '/batch_pubmed_del/:user/:file' => sub {
    # delete saved data file
    my $user = params->{user};
    my $file_name = params->{file}.'.json';
    $file_name = File::Spec->catfile('batch_pubmed_result', $user, $file_name);
    unlink $file_name or return $!;
};

post '/_run_status' => sub {
    
};

dance;

sub scrutinise {
    # check title and abstract if it truely is relevant. Assign a score to both this gene and each ref.
    my %args = @_;
    my @ids = @{$args{ids}};
    my @terms = @{$args{terms}};
    my $email = $args{email};
    my $reg = join '\b|\b', @terms;
    $reg = '\b'.$reg.'\b';
    my $results = {total_score => 0, results => []};
    # ncbi might not respond. this will throw an error. catch and repeat it after 5 sec
    my $factory = Bio::DB::EUtilities->new(
        -eutil   => 'efetch',
        -email   => $email,
        -db      => 'pubmed',
        -retmode => 'xml',
        -id      => \@ids
    );
    my $err = 1;
    my $xml;
    while ($err == 1){
        try {
            $xml = $factory->get_Response->content;
            $err = 0;
        } catch {
            warn "$_";
            warn "sleep for 5 sec";
            sleep(5);
        };
    }
    
    my $xml_parser = XML::LibXML->new();
    my $dom = $xml_parser->parse_string($xml);
    my $root = $dom->documentElement();
    my @nodes = $root->getElementsByTagName('MedlineCitation');
    
    for my $node (@nodes) {
        #print Dumper $node;
        my $score = 0;
        my ($pmid) = $node->getChildrenByTagName('PMID');
        $pmid = $pmid->textContent;
        
        my ($title) = $node->getElementsByTagName('ArticleTitle');
        my ($abstract) = $node->getElementsByTagName('Abstract');
        if ($title and my $s = () = $title->textContent =~ /($reg)/g){
            $score += $s;
        }
        if ($abstract and my $s = () = $abstract->textContent =~ /$reg/g){
            $score += $s;
        }
        if ($score){
            my $t = $title ? $title->textContent : ''; my $ab = $abstract ? $abstract->textContent : '';
            push $results->{results}, {id => $pmid, title => $t, abstract => $ab, score => $score};
        }
        $results->{total_score} += $score;
    }
    return $results;
}

sub get_pred_score {
    # for the batch_pubmed route.
    # calculate the pred score
    # [D/A].each = 10, [P].each = 5, [C].each = 6, [T/B/N].each = -1. If there is a splicing/insertion/deletion event, the score is set as 1000. Not given is set as 0
    # ref: https://github.com/plagnollab/DNASeq_pipeline/blob/master/GATK_v2/filtering.md
    my $row = shift;
    my $pred;
    if ($row->{Func} =~ /splic/ or $row->{ExonicFunc} =~ /stop|frame|del|insert/){
        $pred = 1000;
    } else {
        for my $h (keys %$row){
            if ($h =~ /Pred/){
                $pred += do {
                    given ($row->{$h}){
                        when ('D' or 'A'){10};
                        when ('P'){5};
                        when ('C'){6};
                        when ('T' or 'B' or 'N'){-1};
                        default {0};
                    }
                };
            }
        }
    }
    return $pred;
}

1;