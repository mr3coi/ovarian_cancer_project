
##### ============================================================================================
##### ============================================================================================
##### =============== Packages & Initial Settings =================
##### ============================================================================================
##### ============================================================================================

library(e1071)
library(MASS)
library(ROCR)
library(nnet)
library(glmnet)
library(caret)
library(AUC)
library(car)

#require(devtools); devtools::install_github("briatte/ggnet")	### Install if necessary
library(ggnet); library(network); library(sna)

wd 		 <- "/Users/SJC/Documents/practice/internship/ovarian_cancer"
datafile <- "ova_db2.csv" 
varfile  <- "ova_variable.csv" 
setwd(wd) 

source("preproc.R")
source("stepAIC.R")
source("lasso.R")
source("perform_eval.R")
source("util_fn.R")
source("corr_pair.R")

##### ============================================================================================
##### ============================================================================================
##### ============== Variables & Arguments Setting =============
##### ============================================================================================
##### ============================================================================================

##### Read and preprocess source data
ova.db.csv = as.data.frame(read.csv(datafile,skip=2,stringsAsFactors=F,check.names=F)) 

##### Extract relevant portion of the given source data and preprocess it
col_index  = 1:52			### Column indices of explanatory variables to use
resp.var   = "Recurrence"		### Name of response variable
ova.db.csv = preProc(ova.db.csv,c(1:52),resp.var)

##### Extract relevant sub-data.frame from given data	=>	'ova.db.csv.sub'
	### Exclude columns that are obviously meaningless or irrelevant
avoid 		   = c(1,2,30:32)						# 1,2 : date variables
ova.db.csv.sub = ova.db.csv[,-avoid]				# exclude all variables w/ column indices in 'avoid'
resp.ind 	   = which(colnames(ova.db.csv.sub) == resp.var)	# index of response variable

##### Preprocess : remove NA's	=>	'input' (final data form)
row_NA		= apply(ova.db.csv.sub,1,function(v) {sum(is.na(v)) == 0})
input 		= ova.db.csv.sub[row_NA,]

##### temporary storage of 'input' for easier reload
#save(input,file='input.RData')
#load(file='input.RData')




##### ============================================================================================
##### ============================================================================================
##### ============== Collinearity resolution ==================
##### ============================================================================================
##### ============================================================================================

exp.vars = colnames(input)[colnames(input)!=resp.var]

##### Correlation b/w surviving explanatory variables
#cor(input)

##### VIF calculation
vif_alias  = alias(glm(Recurrence ~ ., family=binomial(link=logit), data=input))	### Check for perfect MC

vif_result = vif(glm(Recurrence ~ ., family=binomial(link=logit), data=input))
vif_result = cbind(match(names(vif_result),exp.vars),vif_result)
colnames(vif_result) = c("exp.var_index","vif")
vif_result = vif_result[order(vif_result[,2],decreasing=T),]
vif_high = vif_result[vif_result[,2] > 10,1]
#names(vif_high) = NULL

##### Test for and remove collinear variables
	### Generate matrix of p-values from independence tests for each variable pair
corr.pairs  = pair.indep(input)

	### Plot # of pairs against thresholds for p-value to find optimum threshold
alpha_seq	= c(1 %o% 10^(-3:-15))
pair_count	= sapply(alpha_seq, function(v) { nrow(corr.pairs[corr.pairs[,3] < v,]) })
plot(-log10(alpha_seq),pair_count,xlab="-log10(alpha)",ylab="# of variable pairs",
	 main="dist. of dependent variable pairs\nper threshold")
abline(h=100)
abline(v=5)

	### Extract all pairs w/ p-value < threshold(alpha)	and sort by p-value in increasing order
alpha 		= 1e-5
corr.edit 	= corr.pairs[corr.pairs[,3] < alpha,]
corr.edit 	= corr.edit[order(corr.edit[,3]),]

	### Check names of and plot variable pairs to check whether they are truly correlated
# exp.vars = colnames(input)[colnames(input)!=resp.var]	## potential explanatory variables in 'input'
# var1.ind = 12
# var2.ind = 13
# exp.vars[c(var1.ind,var2.ind)]
# plot(input[,exp.vars[var1.ind]],input[,exp.vars[var2.ind]],xlab=exp.vars[var1.ind],ylab=exp.vars[var2.ind])

	### Plot a network graph for visualization of key variables
	### 	& Remove most highly linked nodes until each node is isolated
nodes	= sort(unique(as.numeric(corr.edit[,-3])))		# Column indices of vars in 'input'
net 	= matrix(0,nc=length(nodes),nr=length(nodes),dimnames=list(nodes,nodes))
for (i in 1:nrow(net)) {
	for (j in (i+1):ncol(net)) {
		if( any((corr.edit[,1] %in% nodes[i] & corr.edit[,2] %in% nodes[j]) |
			(corr.edit[,1] %in% nodes[j] & corr.edit[,2] %in% nodes[i])) ) net[i,j] = net[j,i] = 1
	}
}
exclude_node_val = c() 		### Container for indices of variables in 'input'
							###		that need to be removed due to dependency
include = (1:length(nodes))[!(1:length(nodes)) %in% match(exclude_node_val,nodes)]
net_obj = network(net[include,include],directed=F)
		### Highlight nodes w/ high VIF value
net_obj %v% "vif"   = ifelse(nodes[include] %in% vif_high, "MC", "non-MC")
net_obj %v% "color" = ifelse(net_obj %v% "vif" == "MC", "steelblue", "grey")
network.vertex.names(net_obj) = nodes[include]
ggnet2(net_obj,size=5,label=T,color="color")

while(T) {
	## include : INDICES of vars in 'nodes' that are currently surviving
	include = (1:length(nodes))[!(1:length(nodes)) %in% match(exclude_node_val,nodes)]
	
	## Draw the network graph b/w vars in 'include'
	net_obj = network(net[include,include],directed=F)
	net_obj %v% "vif" = ifelse(include %in% vif_high, "MC", "non-MC")
	network.vertex.names(net_obj) = nodes[include]
	ggnet2(net_obj,size=5,label=T)
	
	## Check # of remaining links (exit if none)
	row.sum = apply(net[include,include],1,sum)
	if (all(row.sum == 0)) break
	
	## Exclude the 'hub' node (node w/ the most links)
	most_link_node = names(row.sum)[which.max(row.sum)]
	exclude_node_val = c(exclude_node_val,most_link_node)
}

	### Check final (isolated) state of variables
ggnet2(net_obj,size=5,label=T)
length(exclude_node_val); exclude_node_val

	### Update 'input' to exclude variables in 'exclude_node_val'
reg_input 	 = input 			### Dataset w/ variables not removed (for regularization)
input 	 	 = input[,-as.numeric(exclude_node_val)]; dim(input)	### Dataset w/ variables removed (for AIC)
reg_resp.ind = resp.ind
resp.ind 	 = which(colnames(input) == resp.var)



##### ============================================================================================
##### ============================================================================================
##### ============== Main Program ==================
##### ============================================================================================
##### ============================================================================================

##### Check if variables still have rare values (freq. < 0.01) and remove corresponding rows
factor_check = unlist(lapply(input,is.factor))			## boolean for factor variables in 'input'
factors = names(factor_check)[factor_check]
tmp 	= apply(input,2,function(v) { any(table(v)/length(v) < 0.01) })
tmp 	= names(tmp)[tmp]
vars 	= tmp[tmp %in% factors]

	### Remove the rows containing such rare values
if (length(vars) > 0) {
	idx = c()
	for (var in vars) {
		tmp 	= input[,var]
		tbl 	= table(tmp) / length(tmp)
		target 	= names(tbl)[which(tbl < 0.01)]
		if (length(target) > 0) {
			#cat(colnames(dataset)[col], '\n')
			#cat(target, '---', which(tmp %in% target), '\n\n')
			idx = c(idx, which(tmp %in% target))
		}
	}
	idx = sort(unique(idx))
	input = input[-idx,] 
}


##### Function call for stepwise AIC
result_AIC	= stepwiseAIC(input,resp.var)

##### Function call for regularized regression
result_auc	= regular.CV(reg_input, resp.ind, crit="auc"); 	 result_auc
result_dev	= regular.CV(reg_input, resp.ind, crit="dev"); 	 result_dev
result_cls	= regular.CV(reg_input, resp.ind, crit="class"); result_cls
result_mae	= regular.CV(reg_input, resp.ind, crit="mae"); 	 result_mae

##### 'marker.mat' generation
AIC_0 = ifelse(colnames(reg_input) %in% colnames(input)[-ncol(input)][result_AIC$step0 == 1],1,0)
AIC_F = ifelse(colnames(reg_input) %in% colnames(input)[-ncol(input)][result_AIC$stepF == 1],1,0)

marker.mat 			 = rbind(AIC_0, AIC_F, result_auc$vars,
					   		 result_dev$vars, result_cls$vars, result_mae$vars)
colnames(marker.mat) = colnames(reg_input[,-resp.ind])
rownames(marker.mat) = c("AIC_0","AIC_F","reg_auc","reg_dev","reg_cls","reg_mae")

##### Run comparison
# k : # of repetitions for CV
eval.result = performance(input, resp.ind, marker.mat, CV.k=c(3,5)); eval.result









##########################################################
########## Things to do #############
##########################################################

# - Check validity of independence-test-based variable reduction process (collinearity part)
#	- Add code to allow manually choosing variables based on prior knowledge
#	- Check why some p-values are >1, and whether it is ok to simply ignore them
#	- Discuss how to undo the 'tangle' b/w variables and choose the best ones
# - Data-related issues
#	- Check whether "Parity" and "Other_sites" are actually categorical variables
#	- Fix flawed data points in the given data
#	- Check if too many variables are removed during preprocessing
#	- Find a way to avoid removing rows again in 'Main Program' stage
# - Discuss the validity / significance of the calculated results
# - lasso.R
#	- Check whether separating training/test sets is necessary for variable selection
# - stepAIC.R
#	- Check the necessity of the codes commented out
# - perform_eval.R
#	- (doLOGIT) difference b/w 'predict' and 'prediction' objects?
# 	- Run kNN w/ various k values