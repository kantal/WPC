#!/usr/bin/env perl

# Weekend Programming Challenge #45
#
# A Perl & R solution by Dimitrios - Georgios Kontopoulos.

=head1 NAME

ecg.pl

=head1 AUTHOR

Dimitrios - Georgios Kontopoulos
<dgkontopoulos@member.fsf.org>

=head1 DESCRIPTION

This Perl/R script solves the L<45th Weekend Programming Challenge
by Olimex|http://olimex.wordpress.com/2014/03/07/weekend-programming-challenge-week-45-median-filter/>.

It reads the ECG-SMT's signal and extracts the measurements for the 1st channel 
at each time point. It tries to ignore the noise within the data with two methods:

=over 3

=item 1
It fits a LOESS model to the data.

=item 2
It applies a multivariate adaptive online repeated median filter to the 
dataset, to ignore the noise.

=back

Both approaches generate similar looking curves. Using the number of outlying peaks
and the hardware specifications, it calculates the heart rate of the individual 
in beats per minute (bpm). Finally, it also generates time series curves of the 
measurements, using both methods.

=head1 DEPENDENCIES

-the Perl interpreter, >= 5.10

-Statistics::R, >= 0.32 (Perl module)

-the R interpreter, >= 3.0.1

-ggplot2, >= 0.9.3.1 (R package)

-grid, >= 3.0.1 (R package)

-robfilter, >= 3.0 (R package)

=cut

use strict;
use warnings;

use feature qw(say);

use Statistics::R;

# Read the signal.
my $signal;
{
    local $/ = undef;
    $signal = <DATA>;
    chomp $signal;
}

# Split the signal to packets.
my @packets = ( $signal =~ m/.{34}/g );

# Store the values for each channel.
my (@el_1);
foreach (@packets)
{
    my ($val_1) = recognize_signal($_);

    push @el_1, $val_1;
}

# Initialize the R bridge object.
my $R = Statistics::R->new;

# Copy the values to R.
$R->set( 'el_1', \@el_1 );

# Create a vector of measurement IDs.
my @ids = ( 1 .. $#el_1 + 1 );
$R->set( 'IDs', \@ids );

# Plot the measurements, using LOESS smoothing.
my $R_code = << 'END';
library(ggplot2)
library(robfilter)

#############################
# F  U  N  C  T  I  O  N  S #
#############################

# Calculate the heart rate, based on the number of the peaks, measurement time
# and frequency (256 Hz).
calc_heart_rate <- function(peaks, dataset)
{
    heart_rate <- length(peaks) * 60 * 256/length(dataset)
    return(round(heart_rate))
}

# Plot multiple panels in one image.
multiplot <- function(..., plotlist = NULL, file, cols = 1, layout = NULL)
{
    require(grid)
    
    # Make a list from the ... arguments and plotlist
    plots <- c(list(...), plotlist)
    
    numPlots = length(plots)
    
    # If layout is NULL, then use 'cols' to determine layout
    if (is.null(layout))
    {
        # Make the panel
        # ncol: Number of columns of plots 
        # nrow: Number of rows needed, calculated from # of cols
        layout <- matrix(seq(1, cols * ceiling(numPlots/cols)), ncol = cols, nrow = ceiling(numPlots/cols))
    }
    
    if (numPlots == 1)
    {
        print(plots[[1]])
        
    } else
    {
        # Set up the page
        grid.newpage()
        pushViewport(viewport(layout = grid.layout(nrow(layout) + 1, ncol(layout), 
            heights = unit(c(0.5, rep(5, ceiling(numPlots/cols))), "null"))))
        grid.text(paste("Heart Rate:", heart_rate_madore, "bpm"), vp = viewport(layout.pos.row = 1, 
            layout.pos.col = 1:2), gp = gpar(fontsize = 18, fontface = "bold"))
        
        # Make each plot, in the correct location
        for (i in 1:numPlots)
        {
            # Get the i,j matrix positions of the regions that contain this subplot
            matchidx <- as.data.frame(which(layout == i, arr.ind = TRUE))
            
            print(plots[[i]], vp = viewport(layout.pos.row = matchidx$row + 1, layout.pos.col = matchidx$col))
        }
    }
}

# Return the positions of the peaks in the dataset.
detect_peaks <- function(x)
{
    return(which(diff(sign(diff(x))) == -2) + 2)
}

# Fit the noisy data to a loess model with span = 0.15.
peaks_from_loess_m <- function(dataset)
{
    X <- 1:length(dataset)
    
    fit <- loess(dataset ~ X, span = 0.15)
    
    Y <- c()
    for (i in 1:length(dataset))
    {
        Y <- c(Y, predict(fit, i))
    }
    return(detect_peaks(as.vector(ts_outliers(Y, 'loess'))))
}

peaks_from_madore_filter <- function(dataset)
{
    return(detect_peaks(as.vector(ts_outliers(dataset, "madore_filter"))))
}

# Round, as it's supposed to be!
round <- function(x)
{
    return(trunc(x + 0.5))
}

# Set all points to 0, except for the ultimate peaks.
ts_outliers <- function(x, model)
{
    x <- as.ts(x)
    if (frequency(x) > 1) 
        resid <- stl(x, s.window = "periodic", robust = TRUE)$time.series[, 3] else
        {
        tt <- 1:length(x)
        resid <- residuals(loess(x ~ tt))
    }
    
    if (model == 'loess')
    {
		resid.q <- quantile(resid, prob = c(0.25, 0.75))    
    } else if (model == 'madore_filter')
    {
		resid.q <- quantile(resid, prob = c(0.15, 0.85))
    }
    iqr <- diff(resid.q)
    limits <- resid.q + 1.5 * iqr * c(-1, 1)
    score <- abs(pmin((resid - limits[1])/iqr, 0) + pmax((resid - limits[2])/iqr, 
        0))
    return(score)
}

############################
# M  A  I  N    C  O  D  E #
############################

peaks_loess <- peaks_from_loess_m(el_1)

m.filter <- madore.filter(as.matrix(el_1), width.search = 'linear')$signals
peaks_madore <- peaks_from_madore_filter(m.filter)

assign("heart_rate_loess", calc_heart_rate(peaks_loess, el_1), envir = .GlobalEnv)
assign("heart_rate_madore", calc_heart_rate(peaks_madore, m.filter), envir = .GlobalEnv)

png(file="./ecg_plots.png", height = 200, width = 700)

dataset1 <- data.frame(Point_ID = IDs, Measurement = el_1)
p1 <- ggplot(dataset1, aes(Point_ID, Measurement)) + geom_point(shape = 21, color = "grey") + 
    geom_smooth(method = "loess", span = 0.15, color = "red3", fill = "orangered", 
        size = 1.1) + ggtitle("LOESS smoothing") + theme(axis.text = element_text(size = 10), 
    axis.title = element_text(size = 10), plot.title = element_text(size = 15, face = "bold"))

dataset2 <- data.frame(Point_ID = IDs, Measurement = m.filter)
p2 <- ggplot(dataset2, aes(Point_ID, Measurement)) + geom_point(shape = 21, color = "grey") + 
    geom_line(color = "red3", size = 1.1) + ylim(0, max(m.filter, na.rm = TRUE)) + 
    ggtitle("Adaptive online repeated median filter") + theme(axis.text = element_text(size = 10), 
    axis.title = element_text(size = 10), plot.title = element_text(size = 15, face = "bold"))

multiplot(p1, p2, cols = 2)

dev.off()
END

# Run the R code.
$R->run($R_code);

# Print the result.
my $heart_rate = $R->get('heart_rate_madore');
say "\nHeart rate: $heart_rate bpm";
say 'See also the "ecg_plots.png" file.';
say q{};

#############################################
# S   U   B   R   O   U   T   I   N   E   S #
#############################################

# Get the hex measurement for the first channel.
sub recognize_signal
{
    my ($packet) = @_;

    if ( $packet =~ /^\w{8}(\w{4})\w{22}$/ )
    {
        return hex $1;
    }
}

__DATA__
A55A02B3029D01FF01FA01F501F001E903A55A02B4028901FF01FA01F501EF01E803A55A02B50216020001F901F401ED01E703A55A02B6020D01FF01FA01F401EE01E703A55A02B7023401FF01FA01F501EF01E803A55A02B8026701FF01FA01F501EF01E903A55A02B901DE020001F901F401EE01E803A55A02BA026101FF01FB01F601F101EA0BA55A02BB026701FF01FA01F601F001EA0BA55A02BC028901FF01FA01F601F001EA0BA55A02BD026E01FF01FA01F501EF01E90BA55A02BE025601FF01FA01F401EE01E80BA55A02BF025201FF01FA01F501EF01E90BA55A02C0023E01FF01FA01F401EE01E80BA55A02C1024F01FF01FA01F501EF01E90BA55A02C2028201FF01FA01F501EF01E90BA55A02C3024401FF01F901F301ED01E703A55A02C4023B01FF01FA01F401EE01E803A55A02C5025901FF01FA01F501EF01E803A55A02C6024601FF01FA01F501EF01EA03A55A02C7027501FF01FA01F501EF01E903A55A02C8025A020001FA01F501EF01E903A55A02C90236020001FB01F701F201ED03A55A02CA023E020101FC01F701F201ED03A55A02CB0257020001FB01F601F101EB03A55A02CC0244020001FB01F601F101EB0BA55A02CD028901FF01FA01F601F001EB0BA55A02CE0292020001FA01F501F001EA0BA55A02CF025C020001FA01F401EE01E70BA55A02D0023B020001FA01F501EF01E90BA55A02D1025101FF01F901F401EE01E70BA55A02D2027A020001FA01F501EF01E80BA55A02D30237020001FA01F401EE01E80BA55A02D40229020001FA01F401EE01E80BA55A02D5027D020001FA01F501EF01E80BA55A02D6025D020001FA01F501EF01E803A55A02D7024B020001FA01F501EF01E903A55A02D80248020001FA01F501EF01E803A55A02D9022C020001FA01F501EF01E903A55A02DA023A020001FA01F501EF01E803A55A02DB024C01FF01FA01F501EF01E803A55A02DC028301FF01FA01F501EF01E903A55A02DD0273020001FB01F601F001EA03A55A02DE025E020001FA01F501EF01E903A55A02DF023001FF01FA01F501F001E90BA55A02E0025B01FF01F901F401EF01E80BA55A02E102AF020001FA01F501EF01E90BA55A02E2023701FF01F901F401EE01E80BA55A02E3022B01FF01FA01F401EE01E80BA55A02E4024C020001FA01F601F001EA0BA55A02E5026F020001FA01F501F001EA0BA55A02E6026C01FF01FA01F501EF01E90BA55A02E70262020001F901F401EE01E70BA55A02E80239020001FA01F401EE01E803A55A02E90225020001FA01F501EF01E803A55A02EA023A020001FA01F501EF01E803A55A02EB0230020001F901F401EF01E803A55A02EC026F020001FB01F601F001EA03A55A02ED0235020001FA01F501EF01E803A55A02EE0275020001FA01F601F001EA03A55A02EF024301FF01FA01F401EE01E803A55A02F00232020001FA01F401EE01E803A55A02F10251020001FA01F501EF01E80BA55A02F2028E01FF01FA01F501F001E90BA55A02F3026A01FF01FA01F501EF01E90BA55A02F4022C020001FA01F401EE01E80BA55A02F50284020001FA01F501F001E90BA55A02F60274020001FA01F501EF01E90BA55A02F7024F020001FB01F601F001EA0BA55A02F802B2020001FB01F701F101EB0BA55A02F902F9020001FB01F701F101EB0BA55A02FA033F020001FA01F501F001EA03A55A02FB02EC020001FA01F501EF01E903A55A02FC0271020001FA01F501EE01E803A55A02FD02B701FF01FA01F501EE01E703A55A02FE0288020001FA01F501EF01E903A55A02FF02B6020001FB01F601F001EA03A55A02000293020001FA01F401EE01E703A55A0201026D01FF01FA01F501EF01E903A55A0202027501FF01F901F401EE01E703A55A0203023501FF01FA01F501EF01E80BA55A0204021501FF01F901F401EE01E80BA55A0205020701FF01FA01F401EE01E80BA55A0206021901FF01FA01F501EF01E80BA55A02070220020001FA01F501EF01E80BA55A0208023D01FF01FA01F501F001EA0BA55A020901E4020001F901F301ED01E70BA55A020A0260020001FB01F601F101EA0BA55A020B021F020001FA01F401EE01E80BA55A020C020C01FF01F901F301ED01E703A55A020D020A01FF01F901F401EE01E703A55A020E01EA01FF01F901F401ED01E703A55A020F022001FF01FA01F401EE01E703A55A0210024401FF01FA01F501EF01E903A55A0211022401FF01F901F301ED01E703A55A021201E201FF01F901F301ED01E703A55A0213022001FF01FA01F401EE01E803A55A0214021D01FF01FA01F401EE01E803A55A0215023201FF01FA01F601F001EA0BA55A02160251020001FA01F501F001EA0BA55A0217028001FF01FA01F501F001EA0BA55A021802B901FF01FA01F601F001EA0BA55A021903BD020001FD01FA01F501EF0BA55A021A03FF020001FD01FB01F601F00BA55A021B03FF01FF01FC01F801F201EB0BA55A021C03FF01FF01F901F601F001E90BA55A021D03FF01FF01FB01F801F201EB0BA55A021E03FF01FF01FC01F901F201EB0BA55A021F036801FF01F901F401ED01E703A55A0220016D01FF01F701F001E901E303A55A0221003701FF01F801F001E901E303A55A0222000701FF01F801F001EA01E303A55A0223001301FF01F801F101EA01E403A55A0224009501FF01F901F201EC01E503A55A022500F7020001F901F301ED01E603A55A0226013F01FF01F901F201EC01E503A55A022701D801FF01F901F401EE01E703A55A0228026201FF01FB01F701F201EB0BA55A0229024E01FF01FA01F501F001EA0BA55A022A021F01FF01F901F401EE01E80BA55A022B025A01FF01FA01F501EF01E90BA55A022C026301FF01FA01F501EF01E90BA55A022D025F020001FA01F501EF01E90BA55A022E026001FF01FA01F501EF01E90BA55A022F025701FF01F901F401EF01E80BA55A0230026201FF01FA01F501EF01E90BA55A0231022901FF01F901F301EC01E603A55A0232021801FF01F901F301ED01E703A55A0233025F01FF01FA01F501EF01E803A55A023402A601FF01FA01F501F001E903A55A0235021301FF01F901F301ED01E703A55A023601FF01FF01F901F401EE01E703A55A0237028201FF01FA01F501F001E903A55A0238028C020001FA01F501F001EA03A55A0239027A01FF01FA01F501EF01E903A55A023A027E01FF01FA01F601F101EB0BA55A023B02AC01FF01FA01F601F001EA0BA55A023C027F01FF01FA01F501EF01E90BA55A023D029001FF01FA01F501EF01E90BA55A023E02AA01FF01FA01F501EF01E90BA55A023F02A201FF01FA01F601F001EA0BA55A024002AC01FF01FA01F501EF01E90BA55A0241026201FF01FA01F501EF01E90BA55A024202E301FF01FA01F601F001EA0BA55A0243031601FF01FA01F501EF01E903A55A024402A601FF01FA01F401EE01E803A55A024502C201FF01FA01F501EF01E903A55A0246029F01FF01FA01F501EF01E903A55A024702DB01FF01FA01F601F001E903A55A0248029F01FF01FA01F501EF01E903A55A024902EE01FF01FB01F601F101EA03A55A024A031A01FF01FB01F601F001EA03A55A024B02E201FF01FA01F601F001EA03A55A024C030F01FF01FB01F701F201EB0BA55A024D031801FF01FA01F601F101EB0BA55A024E031B01FF01FA01F601F101EB0BA55A024F034E01FF01FB01F701F101EB0BA55A0250033201FF01FB01F701F101EB0BA55A0251036701FF01FB01F701F101EB0BA55A0252034E01FF01FA01F601F001EA0BA55A025303A501FF01FB01F701F201EC0BA55A025403F101FF01FB01F801F201EC0BA55A0255038001FF01FA01F501EF01E903A55A02560389020001FB01F701F101EB03A55A025703FF01FF01FB01F801F201EC03A55A025803FF01FF01FB01F701F101EB03A55A025903D101FF01FC01F701F101EB03A55A025A03B601FF01FB01F701F101EB03A55A025B03A201FF01FA01F601F001EA03A55A025C03A701FF01FA01F601F001EA03A55A025D037C01FF01FB01F701F101EB03A55A025E037301FF01FB01F801F201EB03A55A025F038F01FF01FB01F701F201EC0BA55A0260036A01FF01FA01F601F001EA0BA55A0261033D020001FA01F601F001EA0BA55A02620308020001FA01F501EF01E90BA55A026302C701FF01FA01F501EF01E90BA55A026402C901FF01FA01F501EF01E90BA55A0265029101FF01FA01F501EF01E90BA55A0266029901FF01FA01F501EF01E80BA55A0267028901FF01FA01F501EF01E80BA55A0268022501FF01F901F301ED01E703A55A0269024801FF01FA01F401EE01E703A55A026A026F01FF01FA01F501F001E903A55A026B023F01FF01F901F401EE01E703A55A026C021E01FF01FA01F401EE01E803A55A026D023D01FF01FA01F501EF01E803A55A026E0225020001FC01F801F301ED03A55A026F01F3020001FA01F601F001EB03A55A027001F8020001FA01F501EF01EA03A55A02710207020001FA01F501EF01E80BA55A027201E7020001FA01F401EE01E80BA55A027301D601FF01F901F401EE01E70BA55A027401D901FF01F901F401EE01E70BA55A0275020601FF01FA01F401EE01E80BA55A027601F7020001FA01F401EE01E80BA55A027701D8020001FA01F501EF01E90BA55A027801D2020001FA01F401EF01E90BA55A0279021E01FF01FA01F501EF01E90BA55A027A023E020001F901F301ED01E703A55A027B01E1020001FA01F401EE01E703A55A027C01E4020001FA01F401EE01E703A55A027D01ED01FF01FA01F401EE01E803A55A027E020901FF01FA01F501EF01E803A55A027F025C020001FA01F501EF01E903A55A028001F8020001F901F301EC01E603A55A028101D2020001FA01F401EE01E803A55A0282021801FF01F901F401EE01E703A55A028301F501FF01FA01F501EF01E80BA55A0284020201FF01FA01F401EE01E80BA55A0285021301FF01FA01F501EF01E90BA55A02860215020001FA01F501F001EA0BA55A028701BB020001FA01F401EE01E80BA55A028801EC01FF01FA01F401EE01E80BA55A028901DB020001F901F301ED01E70BA55A028A0203020001FA01F501EF01E90BA55A028B01D6020001FA01F401EE01E80BA55A028C024E01FF01FA01F501EF01E803A55A028D01FB020001F901F301ED01E703A55A028E01BA020001F901F301ED01E703A55A028F020B020001FA01F401EE01E703A55A0290022801FF01FA01F501EF01E903A55A029101ED01FF01F901F301ED01E703A55A0292021901FF01FA01F401EE01E703A55A029301D8020001F901F401ED01E703A55A029401DD020001FA01F401EE01E703A55A029501F601FF01FA01F501EF01E90BA55A0296020301FF01FA01F501EF01E90BA55A029701F5020001FA01F401EF01E90BA55A029801F4020001FA01F401EE01E80BA55A029901ED020001FA01F501EF01E90BA55A029A01FA020001FA01F501EF01E90BA55A029B01D601FF01F901F401EE01E80BA55A029C01D8020001F901F401EE01E80BA55A029D0214020001FA01F501EF01E90BA55A029E0231020001F901F401ED01E703A55A029F01DB01FF01F801F201EC01E503A55A02A001B5020001F901F301EC01E603A55A02A101D001FF01F901F401EE01E703A55A02A201C601FF01F901F401EE01E703A55A02A301E201FF01F901F401EE01E803A55A02A4020401FF01FA01F401EE01E803A55A02A501FB020001FA01F401EE01E803A55A02A601B5020001F901F301ED01E703A55A02A701EB020001FA01F401EF01E903A55A02A801DE020001FB01F501F001EA0BA55A02A901D1020001FA01F501EF01E90BA55A02AA020301FF01FA01F501EF01E90BA55A02AB020801FF01F901F401EE01E80BA55A02AC01C6020001FA01F401EE01E80BA55A02AD01BE020001F901F401EE01E70BA55A02AE01B801FF01F901F401EE01E80BA55A02AF01E7020001FA01F401EF01E80BA55A02B00202020001FA01F501EF01E80BA55A02B101C2020001F801F201EB01E503A55A02B201D6020001FA01F401ED01E603A55A02B301F801FF01FA01F401EE01E703A55A02B401F9020001FA01F401EE01E803A55A02B501C5020001F901F401ED01E703A55A02B601F2020001FA01F401EE01E803A55A02B701D7020001FA01F501EF01E903A55A02B801FC020001FA01F501EF01E903A55A02B901F1020001F901F301ED01E703A55A02BA01FD020001FA01F501F001EA0BA55A02BB01B1020001FA01F401EE01E80BA55A02BC01DD020001FA01F501EF01E90BA55A02BD01F901FF01FA01F501EF01E90BA55A02BE01D8020001F901F401EE01E80BA55A02BF01E3020001FA01F401EE01E80BA55A02C001E501FF01F701F001E901E10BA55A02C101CC01FF01F801F201EB01E40BA55A02C201F501FF01F901F301ED01E60BA55A02C301F301FF01F901F301EC01E603A55A02C4021C01FF01FA01F401EE01E803A55A02C5023901FF01FA01F501EF01E803A55A02C6021B01FF01FA01F401EE01E803A55A02C7021E020001FA01F501EF01E803A55A02C8024001FF01FA01F501EF01E903A55A02C9023401FF01FA01F401EE01E803A55A02CA025201FF01FA01F501F001EA03A55A02CB026101FF01FA01F501EF01E903A55A02CC020C01FF01F901F401EF01E90BA55A02CD020901FF01F901F401EE01E80BA55A02CE0200020001F901F401EE01E80BA55A02CF01A8020001F901F301EC01E60BA55A02D0019701FF01F901F401EE01E70BA55A02D1022001FF01FA01F501EF01E80BA55A02D2019C01FF01F901F301EC01E60BA55A02D301AB01FF01F901F401EE01E70BA55A02D401A801FF01F901F401EE01E70BA55A02D5018601FF01F901F201EC01E603A55A02D6019D01FF01F901F301ED01E703A55A02D701CE01FF01F901F401EE01E703A55A02D8018A01FF01F901F301ED01E703A55A02D901A801FF01FA01F401EE01E803A55A02DA018C020001F901F401EE01E803A55A02DB019301FF01F901F301ED01E703A55A02DC016201FF01F901F301ED01E603A55A02DD019701FF01F901F301ED01E703A55A02DE018A01FF01FA01F401EE01E80BA55A02DF01AA01FF01F901F301ED01E60BA55A02E001DD01FF01FA01F501EF01E90BA55A02E101C001FF01F901F401EE01E90BA55A02E2016901FF01F901F301EC01E60BA55A02E301F101FF01FA01F601F101EA0BA55A02E4027D01FF01FA01F601F001EA0BA55A02E5031201FF01FB01F701F201EC0BA55A02E6035A01FF01FB01F701F201EC0BA55A02E703FF01FF01FC01F901F301ED0BA55A02E803FF020001FC01F901F401EE03A55A02E903FF01FF01FC01FA01F401EE03A55A02EA03FF01FF01FC01F901F401EE03A55A02EB03FF01FF01FA01F601EF01E903A55A02EC018001FF01F501F101EA01E503A55A02ED003201FF01F801F101EA01E403A55A02EE000601FF01F801F101EA01E403A55A02EF000101FF01F801F101EA01E403A55A02F00000020001F801F101EB01E403A55A02F1000801FF01F801F101EB01E40BA55A02F2006301FF01F901F201EC01E50BA55A02F300B901FF01F901F301ED01E60BA55A02F4013901FF01F901F301ED01E60BA55A02F5017501FF01F901F301ED01E60BA55A02F6022001FF01FA01F501F001E90BA55A02F7020C01FF01FA01F501EF01E90BA55A02F801FB01FF01FA01F401EE01E80BA55A02F9017301FF01F901F301EC01E60BA55A02FA016F01FF01F901F201EB01E503A55A02FB01F901FF01FA01F501EF01E803A55A02FC01DB01FF01F901F401EE01E803A55A02FD01D001FF01F901F401EE01E703A55A02FE01C101FF01F901F301ED01E703A55A02FF020D01FF01FA01F501EF01E903A55A020001EF01FF01F901F401EE01E703A55A0201020201FF01FA01F501EF01E903A55A0202020201FF01FA01F401EE01E803A55A020301E801FF01FA01F501EF01E90BA55A0204020B01FF01FA01F501EF01E90BA55A0205020401FF01FA01F401EE01E80BA55A0206020A01FF01FA01F501EF01E90BA55A0207022A01FF01FA01F501EF01E90BA55A020801FD01FF01F901F401EE01E80BA55A0209023701FF01FA01F501EF01E80BA55A020A024201FF01FA01F501EF01E90BA55A020B026001FF01FA01F501F001E90BA55A020C022D01FF01F901F301ED01E703A55A020D020B01FF01F901F401ED01E703A55A020E0226020001FA01F501EF01E803A55A020F021901FF01FA01F401EE01E803A55A0210023F01FF01FA01F501EF01E903A55A0211025A01FF01FA01F501EF01E803A55A0212025401FF01FA01F501F101EC03A55A0213023F020001FC01F601EF01E803A55A0214023E01FF01F801F301ED01E703A55A0215029D01FF01FA01F601F001E90BA55A0216025D01FF01FC01F801F401EF0BA55A02170289020001FB01F701F301ED0BA55A021802B1020001FA01F601F001EA0BA55A02190278020001FB01F601F001EA0BA55A021A02B6020001FB01F601F101EB0BA55A021B0303020001FB01F601F101EB0BA55A021C02F4020001FA01F601F001EA0BA55A021D0312020001FB01F601F001EA0BA55A021E0300020001FA01F501EE01E803A55A021F0304020001FA01F601F001EA03A55A0220037F020001FB01F601F001E903A55A0221035E01FF01FB01F701F101EA03A55A02220357020001FB01F701F101EA03A55A0223035801FF01FA01F601F001E903A55A0224033A01FF01FA01F601F001E903A55A0225039001FF01FB01F701F101EB03A55A022603AA020001FB01F801F201EC03A55A0227034B020001FB01F701F101EB0BA55A0228034B020001FC01F801F301ED0BA55A02290383020001FB01F701F201EC0BA55A022A033601FF01FA01F601F001EA0BA55A022B032101FF01FA01F601F001EA0BA55A022C02F9020001FB01F601F001EA0BA55A022D02D7020001FA01F601F001E90BA55A022E02CF020001FA01F501EF01E90BA55A022F029A01FF01FA01F501EF01E90BA55A02300271020001FA01F501EE01E70BA55A02310217020001F901F301EC01E503A55A023201F4020001F901F301ED01E603A55A0233020001FF01F901F401EE01E703A55A0234025301FF01FA01F501EF01E803A55A023501E501FF01F901F301ED01E703A55A023601A0020001F901F301ED01E703A55A023701AF020001FA01F501EF01E903A55A023801C4020001FA01F401EF01E903A55A023901E301FF01FA01F401EF01E903A55A023A01D2020001F901F401EE01E80BA55A023B0131020001FA01F401EE01E80BA55A023C0167020001F901F301ED01E70BA55A023D017601FF01F901F301ED01E70BA55A023E015D01FF01F901F301ED01E70BA55A023F0163020001F901F301ED01E70BA55A02400184020001F901F201EC01E50BA55A0241015901FF01F901F301ED01E70BA55A0242016401FF01F901F301EC01E60BA55A02430162020001F901F201EC01E503A55A0244019901FF01F901F301EC01E603A55A02450168020001F901F301ED01E703A55A02460179020001F901F301ED01E703A55A0247017E020001F901F301ED01E703A55A0248013B01FF01F901F401EE01E903A55A02490158020001F901F301ED01E703A55A024A018A020001FA01F401EE01E803A55A024B016E020001F901F401EE01E703A55A024C016201FF01FA01F501EF01E90BA55A024D015401FF01F901F301EE01E80BA55A024E0189020001F901F301ED01E70BA55A024F019B020001F901F301EC01E50BA55A0250018201FF01F901F401EE01E80BA55A025101A501FF01F801F201EC01E50BA55A025201AC01FF01F901F301ED01E60BA55A02530188020001F901F401EE01E70BA55A025401CB01FF01F801EF01EF01E90BA55A02550194020001FB01F501EE01E803A55A02560139020001FA01F401EE01E803A55A0257018601FF01F901F301ED01E703A55A025801C3020001F801F201EB01E403A55A0259016A020001FA01F501EF01E903A55A025A0171020001F901F401EE01E803A55A025B018601FF01F801F201EC01E603A55A025C0171020001F901F401EE01E803A55A025D0170020001FA01F401EE01E803A55A025E016F020001FA01F401EE01E70BA55A025F017801FF01F901F401EE01E80BA55A0260016601FF01F901F301EC01E60BA55A0261016401FF01F901F301EC01E60BA55A026201AE01FF01F901F301EC01E60BA55A02630188020001F901F401EE01E70BA55A0264016001FF01F901F401EE01E80BA55A0265017B01FF01F701F001E901E20BA55A0266019401FF01F801F101EA01E30BA55A0267018401FF01F801F201EB01E403A55A0268018801FF01F901F301EC01E603A55A0269019701FF01F901F401EE01E703A55A026A014601FF01F901F301EE01E803A55A026B014101FF01F901F301ED01E703A55A026C016001FF01F901F301ED01E703A55A026D018401FF01F901F301ED01E703A55A026E017301FF01F901F301ED01E703A55A026F014201FF01F901F301ED01E703A55A0270013601FF01FA01F401EE01E803A55A0271018701FF01F901F301ED01E60BA55A0272014401FF01F901F301ED01E70BA55A0273016E01FF01F901F301ED01E60BA55A0274016201FF01F901F301ED01E70BA55A0275011801FF01F901F301ED01E70BA55A0276013701FF01F901F301EE01E80BA55A0277015301FF01F901F301EC01E60BA55A0278017F01FF01F901F301ED01E60BA55A0279015701FF01F901F401EE01E70BA55A027A018301FF01F801F201EC01E503A55A027B012D01FF01F901F301ED01E703A55A027C016C01FF01F901F301ED01E603A55A027D019401FF01F901F301ED01E603A55A027E017301FF01F901F301ED01E703A55A027F016801FF01F901F301ED01E703A55A0280014901FF01F901F301ED01E703A55A0281016D01FF01F901F301ED01E703A55A0282015601FF01F901F301ED01E603A55A0283015601FF01F901F401EE01E80BA55A0284018501FF01F901F301ED01E70BA55A028501BD01FF01F901F301EC01E60BA55A0286017E01FF01FA01F401EF01E90BA55A0287018601FF01F901F401EE01E80BA55A0288017B01FF01F901F301ED01E70BA55A0289013B01FF01F901F301ED01E70BA55A028A018301FF01F901F301ED01E70BA55A028B01BC01FF01F901F201EB01E40BA55A028C01D401FF01FA01F401EF01E903A55A028D01A601FF01F901F301ED01E703A55A028E01C701FF01FA01F401EE01E803A55A028F01D201FF01F901F401EE01E703A55A029001A401FF01F901F301EE01E703A55A029101CE01FF01F901F301ED01E703A55A0292019201FF01F901F301ED01E603A55A0293018001FF01F901F301ED01E703A55A0294017401FF01F901F301ED01E703A55A0295018001FF01FA01F501EF01E80BA55A0296017801FF01F901F401EE01E80BA55A0297014201FF01F901F301ED01E70BA55A0298014301FF01F901F301ED01E70BA55A0299015401FF01F901F301ED01E70BA55A029A012E01FF01F901F301ED01E70BA55A029B014201FF01F901F301ED01E70BA55A029C012D01FF01F901F301EC01E60BA55A029D010E01FF01F901F301ED01E60BA55A029E0151020001F901F201EC01E503A55A029F014701FF01F901F301EC01E603A55A02A0012601FF01F901F301EC01E603A55A02A1010B01FF01F901F301ED01E603A55A02A2011B01FF01F901F301ED01E603A55A02A3012F01FF01F901F301ED01E603A55A02A4015101FF01F901F301ED01E603A55A02A50115020001F901F301ED01E703A55A02A6012501FF01F901F301EC01E603A55A02A700B2020001F901F301ED01E70BA55A02A800F201FF01F901F301ED01E70BA55A02A9016E01FF01F901F201EC01E60BA55A02AA01A301FF01F801F201EB01E50BA55A02AB025C01FF01FB01F601F101EC0BA55A02AC030D01FF01FB01F801F201EC0BA55A02AD03C701FF01FC01F901F401ED0BA55A02AE03FF020001FC01F901F401EE0BA55A02AF03FF01FF01FC01FA01F501EF0BA55A02B003FF01FF01FC01F901F301EE0BA55A02B103BC020001FA01F601EF01E903A55A02B20172020001F801F101E901E403A55A02B3003201FF01F801F001E901E303A55A02B4000601FF01F801F101EA01E303A55A02B50001020001F801F001EA01E403A55A02B6000001FF01F801F101EA01E403A55A02B70000020001FA01F501F001EB03A55A02B80000020001FA01F301EE01E903A55A02B90087020001F901F301EF01E903A55A02BA014501FF01F901F301ED01E70BA55A02BB018D020001FA01F401EE01E70BA55A02BC0164020001FA01F401EE01E80BA55A02BD015D01FF01F901F301ED01E70BA55A02BE016D020001F901F301ED01E70BA55A02BF0170020001F901F301ED01E70BA55A02C00144020001F901F301EC01E60BA55A02C10123020001F901F401EE01E80BA55A02C2015A01FF01F801F201EC01E50BA55A02C3019C020001F801F101EB01E403A55A02C40186020001F901F301EC01E603A55A02C5019A020001F901F301ED01E603A55A02C601EC020001FA01F501EF01E903A55A02C70129020001F901F301ED01E803A55A02C80156020001F901F301EE01E803A55A02C901A3020001F901F301EC01E603A55A02CA01C201FF01F901F201EB01E403A55A02CB01C6020001FA01F501EF01E903A55A02CC0190020001FB01F601F001EB0BA55A02CD01AD01FF01F901F401EE01E80BA55A02CE0195020001FA01F401EE01E80BA55A02CF01D6020001FA01F401EE01E80BA55A02D001D7020001FA01F501EF01E90BA55A02D101CA020001F901F301ED01E60BA55A02D201B3020001F901F301ED01E70BA55A02D301AE020001F901F301ED01E70BA55A02D401CE020001FA01F401EE01E80BA55A02D501FC020001FA01F401EE01E703A55A02D601C9020001F901F301ED01E703A55A02D701F8020001FA01F501EF01E903A55A02D801F5020001FA01F401EE01E703A55A02D901D6020001FA01F501EF01E903A55A02DA01EF020001FA01F501EF01E903A55A02DB01EE020001FA01F401EE01E803A55A02DC01F8020001FA01F401EF01E803A55A02DD0237020001FA01F501EF01E903A55A02DE0237020001FB01F601F001E90BA55A02DF0247020001FA01F501F001EA0BA55A02E0023F01FF01F901F401EE01E70BA55A02E1023A020001FA01F401EE01E80BA55A02E20277020001FA01F501EF01E90BA55A02E30286020001FA01F501EF01E90BA55A02E402B6020001FB01F601F001EA0BA55A02E502BB020001FB01F701F101EB0BA55A02E602D3020001FA01F601F001EA0BA55A02E702C1020001F901F401ED01E703A55A02E802AA020001FB01F601F001E903A55A02E902C2020001FB01F601F001EA03A55A02EA02C9020001FA01F601F001EA03A55A02EB02AE020001FA01F501EF01E903A55A02EC02FE020001FB01F701F101EB03A55A02ED0333020001FB01F701F101EB03A55A02EE0347020001FB01F701F101EB03A55A02EF02D801FF01FA01F501EF01E903A55A02F0028B020001FA01F601F001EA0BA55A02F102E9020001FA01F501EF01E90BA55A02F202BA020001FA01F501EF01E90BA55A02F302BE020001FA01F501EF01E90BA55A02F40241020001F901F401ED01E70BA55A02F501DB020001F901F301ED01E60BA55A02F6020001FF01FA01F401EE01E70BA55A02F70203020001FA01F501EF01E90BA55A02F801D4020001FA01F401EE01E80BA55A02F9018F020001F901F201EC01E60BA55A02FA0171020001F901F201EC01E503A55A02FB0175020001FA01F401EE01E703A55A02FC0178020001F901F401EE01E703A55A02FD015001FF01F901F401EE01E803A55A02FE011B020001F901F301ED01E703
