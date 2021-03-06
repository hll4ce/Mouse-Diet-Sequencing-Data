# Hampton Leonard

source("https://bioconductor.org/biocLite.R")
library(dada2)
library(ggplot2)
library(DESeq2)
library(phyloseq)
library(randomForest)
library(dplyr)
library(knitr)



path <- "C:/Users/hll4c/R/Mouse Data/Unzipped_final"

fns <- list.files(path)
fns


fastqs <- fns[grepl(".fastq$", fns)]

fastqs <- sort(fastqs) # Sort ensures forward/reverse reads are in same order

fnFs <- fastqs[grepl("_R1", fastqs)] # Just the forward read files
fnRs <- fastqs[grepl("_R2", fastqs)] # Just the reverse read files


# Get sample names from the first part of the forward read filenames
sample.names <- sapply(strsplit(fnFs, "_"), `[`, 1)
sample.names


# Fully specify the path for the fnFs and fnRs
fnFs <- file.path(path, fnFs)
fnRs <- file.path(path, fnRs)





par(mfrow=c(2,3))
#forward
plotQualityProfile(fnFs[[1]])
plotQualityProfile(fnFs[[5]])
plotQualityProfile(fnFs[[13]])
plotQualityProfile(fnFs[[17]])

#reverse
plotQualityProfile(fnRs[[1]])
plotQualityProfile(fnRs[[5]])
plotQualityProfile(fnRs[[13]])
plotQualityProfile(fnRs[[17]])


# Make directory and filenames for the filtered fastqs
filt_path <- file.path(path, "filtered")
if(!file_test("-d", filt_path)) dir.create(filt_path)
filtFs <- file.path(filt_path, paste0(sample.names, "_F_filt.fastq.gz"))
filtRs <- file.path(filt_path, paste0(sample.names, "_R_filt.fastq.gz"))


# Filter only forward reads, reverse reads too low quality to use
for(i in seq_along(fnFs)) {
  fastqFilter(fnFs[i], filtFs[i],
                    trimLeft=20, truncLen=200, 
                    maxN=0, maxEE=2, truncQ=2, 
                    compress=TRUE, verbose=TRUE)
}


derepFs <- derepFastq(filtFs, verbose=TRUE)


# Name the derep-class objects by the sample names
names(derepFs) <- sample.names


derepFs[[1]]


# Sample Inference
dadaFs <- dada(derepFs, err=NULL, selfConsist = TRUE)


 #Visualize error rates
 plotErrors(dadaFs[[2]], nominalQ=TRUE)


# construct sequence table
seqtab <- makeSequenceTable(dadaFs)
dim(seqtab)
table(nchar(colnames(seqtab)))


# Remove chimeras
seqtab.nochim <- removeBimeraDenovo(seqtab, verbose=TRUE)
dim(seqtab.nochim)
sum(seqtab.nochim)/sum(seqtab)
#0.8267492


# assign taxonomy
path2 <- "C:/Users/hll4c/R/Mouse Data"

taxa <- assignTaxonomy(seqtab.nochim, paste(path2,"/rdp_train_set_14.fa.gz",sep = ""))
taxa.plus <- addSpecies(taxa, paste(path2,"/rdp_species_assignment_14.fa.gz",sep = ""))
colnames(taxa.plus) <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus","Species")
unname(taxa.plus)



# Phyloseq analysis

# load metadata for sorting
sample <- read.csv("C:/Users/hll4c/R/SampleMouse.csv")


# Make a data frame holding the sample data
rownames(sample) <- sample$SAMPLE_ID
samples.out <- rownames(seqtab.nochim)
sample <- sample[samples.out,]
diet_description = sample$Diet_and_des
days_on_diet = sample$Days.on.diet


# save seqtab.nochim and taxa.plus for analysis w/ metagenomeSeq
write.table(t(seqtab.nochim), file="C:/Users/hll4c/R/Mouse Data/seqtab.nochim.tsv", quote=FALSE, sep='\t', col.names = NA)
write.table(taxa.plus, file="C:/Users/hll4c/R/Mouse Data/taxa.plus.tsv", quote=FALSE, sep='\t', col.names = NA)


samdf <- data.frame(sample=samples.out, description=diet_description, day=days_on_diet)
rownames(samdf) <- samples.out


# copy to create a new object that has taxa information to make phyloseq object
seqtab.nochim.taxa <- seqtab.nochim
colnames(seqtab.nochim.taxa) <- 1:nrow(taxa.plus)
taxa.table <- taxa.plus
rownames(taxa.table) <- 1:nrow(taxa.plus)





# Construct phyloseq object 
ps <- phyloseq(otu_table(seqtab.nochim.taxa, taxa_are_rows=FALSE), 
               sample_data(samdf), 
               tax_table(taxa.table))
ps

alpha_div <- estimate_richness(ps)
kable(alpha_div)

# Filter sequences that have less than 10 counts in any sample
ps.count <- filter_taxa(ps, function(x) max(x) > 10, TRUE)
ps.count


#convert day values to factor for DESeq
sample_data(ps.count)$day <- factor(sample_data(ps.count)$day)

# Create separate object for comparisons at each time point
d0_subset <- prune_samples(sample_data(ps.count)$day == 0, ps.count)
d5_subset <- prune_samples(sample_data(ps.count)$day == 5, ps.count)
d8_subset <- prune_samples(sample_data(ps.count)$day == 8, ps.count)
d12_subset <- prune_samples(sample_data(ps.count)$day == 12, ps.count)
d15_subset <- prune_samples(sample_data(ps.count)$day == 15, ps.count)
d23_subset <- prune_samples(sample_data(ps.count)$day == 23, ps.count)



# Day 0 comparison ############
deseq2_input_d0 <- phyloseq_to_deseq2(d0_subset,~description)
deseq2_output_d0 <- DESeq(deseq2_input_d0, test="Wald", fitType="parametric")
deseq2_results_d0 <- results(deseq2_output_d0, cooksCutoff = FALSE)

alpha = 0.05
sigtab_d0 = deseq2_results_d0[which(deseq2_results_d0$padj < alpha), ]
sigtab_d0

#No results less than specified alpha, indicates no initial differences in groups



# Day 5 comparison
deseq2_input_d5 <- phyloseq_to_deseq2(d5_subset,~description)
deseq2_output_d5 <- DESeq(deseq2_input_d5, test="Wald", fitType="parametric")
deseq2_results_d5 <- results(deseq2_output_d5, cooksCutoff = FALSE)

alpha = 0.05
sigtab_d5 = deseq2_results_d5[which(deseq2_results_d5$padj < alpha), ]
sigtab_d5 = cbind(as(sigtab_d5, "data.frame"), as(tax_table(ps.count)[rownames(sigtab_d5), ], "matrix"))
head(sigtab_d5)
sigtab_d5

# Day 8 comparison
deseq2_input_d8 <- phyloseq_to_deseq2(d8_subset,~description)
deseq2_output_d8 <- DESeq(deseq2_input_d8, test="Wald", fitType="parametric")
deseq2_results_d8 <- results(deseq2_output_d8, cooksCutoff = FALSE)

alpha = 0.05
sigtab_d8 = deseq2_results_d8[which(deseq2_results_d8$padj < alpha), ]
sigtab_d8 = cbind(as(sigtab_d8, "data.frame"), as(tax_table(ps.count)[rownames(sigtab_d8), ], "matrix"))
head(sigtab_d8)


# Day 12 comparison
deseq2_input_d12 <- phyloseq_to_deseq2(d12_subset,~description)
deseq2_output_d12 <- DESeq(deseq2_input_d12, test="Wald", fitType="parametric")
deseq2_results_d12 <- results(deseq2_output_d12, cooksCutoff = FALSE)

alpha = 0.05
sigtab_d12 = deseq2_results_d12[which(deseq2_results_d12$padj < alpha), ]
sigtab_d12 = cbind(as(sigtab_d12, "data.frame"), as(tax_table(ps.count)[rownames(sigtab_d12), ], "matrix"))
head(sigtab_d12)


# Day 15 comparison
deseq2_input_d15 <- phyloseq_to_deseq2(d15_subset,~description)
deseq2_output_d15 <- DESeq(deseq2_input_d15, test="Wald", fitType="parametric")
deseq2_results_d15 <- results(deseq2_output_d15, cooksCutoff = FALSE)

alpha = 0.05
sigtab_d15 = deseq2_results_d15[which(deseq2_results_d15$padj < alpha), ]
sigtab_d15 = cbind(as(sigtab_d15, "data.frame"), as(tax_table(ps.count)[rownames(sigtab_d15), ], "matrix"))
head(sigtab_d15)


# Day 23 comparison
deseq2_input_d23 <- phyloseq_to_deseq2(d23_subset,~description)
deseq2_output_d23 <- DESeq(deseq2_input_d23, test="Wald", fitType="parametric")
deseq2_results_d23 <- results(deseq2_output_d23, cooksCutoff = FALSE)

alpha = 0.05
sigtab_d23 = deseq2_results_d23[which(deseq2_results_d23$padj < alpha), ]
sigtab_d23 = cbind(as(sigtab_d23, "data.frame"), as(tax_table(ps.count)[rownames(sigtab_d23), ], "matrix"))
head(sigtab_d23)


# Get sequences that were significantly different in each comparison
seqs <- union(rownames(sigtab_d5),rownames(sigtab_d8))
seqs <- union(seqs,rownames(sigtab_d12))
seqs <- union(seqs,rownames(sigtab_d15))
seqs <- union(seqs,rownames(sigtab_d23))


# Transform sequence table from counts to relative abundance
ps.rel <- transform_sample_counts(ps.count, function(x) x/sum(x))
ps.rel

p <- plot_heatmap(prune_taxa(seqs,ps.rel),"NMDS","bray",sample.label = "description","Genus", first.sample = "Plate3-A3")
p + theme (axis.text.x = element_text(size=6))









# Random Forest Modeling

# make dataframe of training data from OTU table with samples as rows and OTUs as columns

ps.rel_pruned <- prune_taxa(seqs,ps.rel)


predictors <- (otu_table(ps.rel_pruned))

dim(predictors)


# make response variable column

response <- as.factor(sample_data(ps.rel_pruned)$description)
otu_table(ps.rel_pruned)
tax_table(ps.rel_pruned)


# combine into one frame

rf_data <- data.frame(response, predictors)


# model


set.seed(1000)

diet.classify <- randomForest(response~., data = rf_data, ntree = 214)
print(diet.classify)
plot(diet.classify)


names(diet.classify)

# predictor names and importance


imp <- importance(diet.classify)
imp <- data.frame(predictors = rownames(imp), imp)


# order by importance

imp.sort <- arrange(imp, desc(MeanDecreaseGini))
imp.sort$predictors <- factor(imp.sort$predictors, levels = imp.sort$predictors)


# plot top 20 most important 

imp.20 <- imp.sort[1:20, ]

ggplot(imp.20, aes(x = predictors, y = MeanDecreaseGini)) +
  geom_bar(stat = "identity", fill = "indianred") +
  coord_flip() +
  ggtitle("Most important OTUs")




# match names in tax table and otu table

otunames <- imp.20$predictors
otunames <- gsub("X", "",  otunames)


r <- rownames(tax_table(ps.rel)) %in% otunames



k <- as.data.frame((tax_table(ps.rel)[r, ]))

t <- k[match(otunames, rownames(k)),]

kable(t)



#Heatmap for most important otus for classifying each day + diet

p <- plot_heatmap(prune_taxa(seqs,ps.rel),"NMDS","bray",sample.label = "description","Genus", first.sample = "Plate3-A1")
p + theme (axis.text.x = element_text(size=6))








#Investigating Lactobacilli populations

tabletax <- as.data.frame(taxa.table)
seqtab.final <- seqtab.nochim.taxa
colnames(seqtab.final) <- tabletax$Genus

lacto <- subset_taxa(ps.rel, Genus == "Lactobacillus")

# group by sample
plot_bar(lacto, "sample", "Abundance", "Genus", title = "Lactobacilli by Sample")

#group by diet
plot_bar(lacto, "description", "Abundance", "Genus", title = "Lactobacilli by Diet")

write.table(seqtab.final, "DADA2_Diet_Seq_Table.csv")

# Resources:
# 1. Base code by Greg Medlock: 
#    https://github.com/gregmedlock/crypto_2016/blob/master/bin/crypto_dada2_processing.R
#
# 2. DADA2 Pipeline Tutorial:
#    http://benjjneb.github.io/dada2/tutorial.html


