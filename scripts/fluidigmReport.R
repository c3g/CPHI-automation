
##############################################################################
### Script to parse Fluidigm genotyping output from McGill Genome Centre   ###
### Filter by quality, call sex, and populate report json.                 ###
### Create visual summary report.                                          ###
### Mareike Janiak, Canadian Centre for Computational Genomics             ###
### Last updated 2025-07-09                                                ###
##############################################################################
### Usage : Rscript fluidigmReport.R -f input_file -s somalier_file -o output_dir

usage <- function(errM) {
    cat("\nUsage : Rscript fluidigmReport.R [option] <Value>\n")
    cat("       -f      : fluidigm file\n")
    cat("       -s      : somalier file\n")
    cat("       -j      : json file\n")
    cat("       -o      : output directory\n")
    cat("       -h      : this help\n\n")
    stop(errM)                
}


args <- commandArgs(trailingOnly = T)

## default arg values
fluidigm_file <- ""
somalier_file <- ""
json_file <- ""
out_path <- ""

## get arg variables
for (i in 1:length(args)) {
    if (args[i] == "-f") {
                fluidigm_file <- as.character(args[i+1])
    
    } else if (args[i] == "-s") {
                somalier_file <- as.character(args[i+1])

    } else if (args[i] == "-j") {
                json_file <- as.character(args[i+1])

    } else if (args[i] == "-o") {
                out_path <- as.character(args[i+1])
    
    } else if (args[i] == "-h") {
                usage("")
        
    }
    
}

## check that files exist
if (!(file.exists(fluidigm_file))) {
        usage("Error : Fluidigm file not found")

}
if (!(file.exists(somalier_file))) {
        usage("Error : Somalier file not found")

}
if (!(file.exists(json_file))) {
        usage("Error : json report file not found")

}
if (out_path == "") {
        usage("Error : Output directory not specified")

}

# remove trailing "/" if necessary
tmpOP <- strsplit(out_path, "")
if (tmpOP[[1]][length(tmpOP[[1]])] == "/") {
    out_path <- paste(tmpOP[[1]][1:(length(tmpOP[[1]])-1)], collapse="")

}

plate_barcode <- read.csv(fluidigm_file, header = FALSE)[1,3]

SCRIPT_HOME <- Sys.getenv("SCRIPT_HOME")
fluidigm_markdown <- paste(SCRIPT_HOME, "/scripts/fluidigmReport.Rmd", sep="")

# render report
rmarkdown::render(input = fluidigm_markdown,
                  params = list(
                                fluidigm_file = fluidigm_file,
                                somalier_file = somalier_file,
                                json_file = json_file                                    
                                ),
                  output_dir = out_path,
                  output_file = paste("fluidigm_qc.",plate_barcode,".html",sep="")
                  )

