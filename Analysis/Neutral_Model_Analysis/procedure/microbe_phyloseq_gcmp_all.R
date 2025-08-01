#Loading Required libraries
library(qiime2R)
library(phyloseq)
library(tidyverse)
library(btools)
library(picante)
library(ggplot2)
library(gplots)
library(RColorBrewer)
library(tidyverse)
library(minpack.lm)
library(Hmisc)
library(stats4)


#Step 1: Import qiime2 tables, mapping, taxonomy, tree and coral phylogeny across mucus tissue and skeleton
#Get user input and assign to variables
args <- commandArgs(trailingOnly=TRUE)
feature_table_path <-args[1]
metadata_path <-args[2]
taxonomy_path <-args[3]
tree_path <-args[4]
coral_tree_path <-args[5]

sink_name = paste0("GCMP_","Phyloseq_Faith_PD_log.txt")
sink(sink_name,append=FALSE,split=TRUE)

####Import from .qza file into a phyloseq object

print(paste("feature_table",feature_table_path))
asv <- qza_to_phyloseq(features = feature_table_path)

#### Import Metadata read.table
metadata <- read.table(file = metadata_path,header=T, comment.char="",row.names=1, sep="\t")

#### Import Tree file from biom output tree.nwk

print(paste("tree_path",tree_path))
tree <- read_tree(tree_path)

coral_tree <-read_tree(coral_tree_path)

#### Import taxonomy from biom output as .tsv format using read.table

print(paste("Loading Taxonomy text files from path:", taxonomy_path))
taxonomy <- read.table(file = taxonomy_path, sep = "\t", header = T ,row.names = 1)

#        **code referenced from Yan Hui: email me@yanh.org github: yanhui09**

tax <- taxonomy %>%
  select(Taxon) %>% 
  separate(Taxon, c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species"), "; ")

tax.clean <- data.frame(row.names = row.names(tax),
                        Kingdom = str_replace(tax[,1], "k__",""),
                        Phylum = str_replace(tax[,2], "p__",""),
                        Class = str_replace(tax[,3], "c__",""),
                        Order = str_replace(tax[,4], "o__",""),
                        Family = str_replace(tax[,5], "f__",""),
                        Genus = str_replace(tax[,6], "g__",""),
                        Species = str_replace(tax[,7], "s__",""),
                        stringsAsFactors = FALSE)

tax.clean[is.na(tax.clean)] <- ""
tax.clean[tax.clean=="__"] <- ""

for (v in 1:nrow(tax.clean)){
  if (tax.clean[v,7] != ""){
    tax.clean$Species[v] <- paste(tax.clean$Genus[v], tax.clean$Species[v], sep = " ")
  } else if (tax.clean[v,2] == ""){
    kingdom <- paste("Unclassified", tax.clean[v,1], sep = " ")
    tax.clean[v, 2:7] <- kingdom
  } else if (tax.clean[v,3] == ""){
    phylum <- paste("Unclassified", tax.clean[v,2], sep = " ")
    tax.clean[v, 3:7] <- phylum
  } else if (tax.clean[v,4] == ""){
    class <- paste("Unclassified", tax.clean[v,3], sep = " ")
    tax.clean[v, 4:7] <- class
  } else if (tax.clean[v,5] == ""){
    order <- paste("Unclassified", tax.clean[v,4], sep = " ")
    tax.clean[v, 5:7] <- order
  } else if (tax.clean[v,6] == ""){
    family <- paste("Unclassified", tax.clean[v,5], sep = " ")
    tax.clean[v, 6:7] <- family
  } else if (tax.clean[v,7] == ""){
    tax.clean$Species[v] <- paste("Unclassified ",tax.clean$Genus[v], sep = " ")
  }
}


### create matrix format for OTU and taxonomy table

print(paste("Loading metadata files from path:", metadata_path))
OTU <- otu_table(as.matrix(asv), taxa_are_rows = TRUE)
tax1 = tax_table(as.matrix(tax.clean))


# Set metadata
SAMPLE <- sample_data(metadata)

# Create Working phyloseq object
main_phylo <- phyloseq(OTU,tax1,SAMPLE,tree)

# visualize tax table
table(tax_table(main_phylo)[,"Kingdom"])

# remove unknown bacteria or unassigned
phylo_noking <-main_phylo %>%
  phyloseq::subset_taxa(!Kingdom %in% c("Unassigned","Unclassified d__Bacteria","d__Eukaryota")) %>%
  phyloseq::subset_taxa(!Phylum %in% c("Unclassified Unassigned","Unclassified d__Archaea","Unclassified d__Bacteria","Unclassified d__Eukaryota")) %>%
  phyloseq::subset_taxa(!Family %in% c("Mitochondria","Chloroplast"))

# verify present taxa in table
table(tax_table(phylo_noking)[,"Kingdom"])

# Remove any samples with less than 1 read
phylo = prune_samples(sample_sums(phylo_noking)>1, phylo_noking)
phylo

print(paste("Starting Loop across compartments"))
## Start for loop across compartments

compartment <- c("M","T","S")
for (i in compartment){
# Subset only corals from database
subject <-subset_samples(phylo, outgroup == "n" & tissue_compartment == print(paste(i)))
subject


### rarefy to even depth

print(paste("Generating Rarefied Coral dataset..."))
rarefied = rarefy_even_depth(subject, rngseed=111, sample.size=1000, replace=F, trimOTUs = TRUE)
rarefied

#### Agglomerate taxa to family 

print(paste("Agglomerated Taxonomy to the Family Level"))
glom <- tax_glom(rarefied, taxrank = 'Family', NArm = TRUE)
glom
#### create ASV tables by id ** This file will be used in microbe_neutral_compartment.R and picrust2_neutral_table_generator.R

print(paste("Generating Agglomerated ASV Table dataset..."))
phyloseq::otu_table(glom)%>%
  as.data.frame()%>%
  rownames_to_column("id") -> glom_otu_table

## Output .tsv from the otu table file
glom_otu_name <- paste0(i,"_glom_table.tsv")
write.table(glom_otu_table, file =glom_otu_name ,sep = "\t",row.names = FALSE)

#### create taxonomy tables by id  ** This 

paste(print("Printing Agglomerated Taxonomy Table"))
phyloseq::tax_table(glom)%>%
  as.data.frame() %>%
  rownames_to_column("id") %>%
  select(-c("Genus","Species"))-> glom_taxonomy

## Output .tsv from the taxonomy file
glom_taxonomy_name <- paste0(i,"_glom_taxonomy.tsv")
write.table(glom_taxonomy, file =glom_taxonomy_name,sep = "\t", row.names = FALSE)

paste(print("Creating glom mapping file"))
phyloseq::sample_data(glom)%>%
  as.data.frame() -> glom_mapping

## Output .csv from the taxonomy file
glom_mapping_name <- paste0(i,"_glom_metadata.csv")
write.table(glom_mapping, file =glom_mapping_name,sep = ",", row.names = FALSE)

#### Subset taxonomy tables ** This table contains non-agglomerated ASV ID which can be used 
#### for comparative analysis of significant non-neutral microbes. 

## Subset rarefied taxonomy 
#paste(print("Subset taxonomy rarefied phyloseq object..."))
#phyloseq::tax_table(rarefied)%>%
#  as.data.frame() %>%
#  rownames_to_column("id") -> rare_taxonomy

## Output .tsv from the rarefied taxonomy file
#rare_file_name <- paste0(i,"_rarefied_taxonomy.tsv")
#write.table(rare_taxonomy, file =rare_file_name, sep = ",",row.names = FALSE)

## Subset Rarefied otu table 
#paste(print("Subset taxonomy rarefied phyloseq object..."))
#phyloseq::otu_table(rarefied)%>%
#  as.data.frame() %>%
#  rownames_to_column("id") -> rare_otu_table

## Output .tsv from the rarefied taxonomy file
#rare_otu_name <- paste0(i,"_rarefied_table.tsv")
#write.table(rare_otu_table, file =rare_otu_name, sep = ",",row.names = FALSE)

#### Join asv and taxonomy tables by id **This will be used in microbe_picrust2_neutral_table_generator.R
#paste(print("Joining OTU and taxonomy tables from agglomerated Phyloseq object..."))
#phyloseq::tax_table(rarefied)%>%
#  as.data.frame()%>%
#  rownames_to_column("id")%>%
#  right_join(phyloseq::otu_table(rarefied)%>%
 #              as.data.frame()%>%
#               rownames_to_column("id")) -> rare_tax_table

## Output joined rarefied taxonomy and otu table
#rare_tax_name <- paste0(i,"_raredied_tax_table.tsv")
#write.table(rare_tax_table, file =rare_tax_name, sep = ",",row.names = FALSE)



########### Calculate Faiths Pd ############
print(paste("Calculating Faith Pd for host and microbiome from **Rarefied** dataset"))
## pull out sample data 
phyloseq::sample_data(rarefied) %>%  
  group_by(sample_name_backup, expedition_number,BiologicalMatter) %>%
 as.data.frame() %>%
  select(sample_name_backup, expedition_number,BiologicalMatter) -> microbial_faith

## Microbial Phyloseq Pd analysis 
estimate_pd(rarefied) %>%
  as.data.frame() -> microbial_faith_pd

microbial_faith$faith_pd <- microbial_faith_pd$PD
microbial_faith$faith_SR <- microbial_faith_pd$SR


## Create data frame from sample data 
phyloseq::sample_data(rarefied) %>%  
  group_by(expedition_number, BiologicalMatter,Huang_Roy_tree_name) %>%
  as.data.frame() %>%
  select(expedition_number, BiologicalMatter,Huang_Roy_tree_name)-> test_df

## Create a new column titled eco to join expedition and biological matter
test_df$eco <-paste(test_df$expedition_number,test_df$BiologicalMatter, sep = "_")

## group and count total for each unique group maintaining NA values
test_df %>% group_by(eco, Huang_Roy_tree_name) %>%  summarise(counts=n()) %>%
  ungroup %>%
  complete(nesting(eco),
           nesting(Huang_Roy_tree_name),
          fill = list(quantity = 0)) -> test_table
## Fill NA with 0
test_table[is.na(test_table)] <-0

## Build Matrix
e <- unique(test_table$eco) 
t <- unique(test_table$Huang_Roy_tree_name) 
c <- test_table$counts

test_matrix <- matrix(c, nrow = length(e), ncol = length(t), byrow=TRUE)
rownames(test_matrix) = e
colnames(test_matrix) = t

# clean data set to match each other
clean_tree <- match.phylo.comm(phy = coral_tree, comm = test_matrix)$phy
clean_comm <- match.phylo.comm(phy = coral_tree, comm = test_matrix)$comm

coral_faith_pd <- pd(clean_comm, clean_tree, include.root=TRUE)
coral_faithpd_reorded <-coral_faith_pd[order(coral_faith_pd$PD, decreasing=TRUE),] 

write.table(microbial_faith, file =paste0(i,"_","microbial_faithpd_table.tsv"), sep = ",",row.names =TRUE, col.names = TRUE)

write.table(coral_faithpd_reorded, file =paste0(i,"_","Host_faithpd_table.tsv") ,row.names = TRUE)
}

print(paste("Finished!"))
