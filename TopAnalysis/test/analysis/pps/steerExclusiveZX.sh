#!/bin/bash

WHAT=$1; 
if [ "$#" -ne 1 ]; then 
    echo "steerExclusiveZX.sh <SEL/MERGE/PLOT/WWW>";
    echo "   SEL          - launches selection jobs to the batch, output will contain summary trees and control plots"; 
    echo "   MERGESEL     - merge output"
    echo "   PLOTSEL      - make plots"
    echo "   WWWSEL       - move plots to web-based are"
    echo "   TRAINPUDISCR - train pileup discriminator"
    echo "   RUNPRED      - run pileup discriminator prediction"
    echo "   PREPAREANA   - prepare bank of events for event mixing from the summary trees"
    echo "   COLLECTMIX   - collects all the mixing events found in PREPAREANA"
    echo "   ANA          - run analysis on the summary trees"
    echo "   PLOTANA      - plot analysis results"
    exit 1; 
fi

#to run locally use local as queue + can add "--njobs 8" to use 8 parallel jobs
queue=tomorrow
githash=ab05162
eosdir=/store/cmst3/group/top/RunIIReReco/${githash}
outdir=/store/cmst3/user/psilva/ExclusiveAna/${githash}
signal_json=$CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/signal_samples.json
plot_signal_json=$CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/plot_signal_samples.json
samples_json=$CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/samples.json
jetht_samples_json=$CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/jetht_samples.json
zx_samples_json=$CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/zx_samples.json
zbias_samples_json=$CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/zbias_samples.json
RPout_json=$CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/golden_noRP.json
wwwdir=~/www/ExclusiveAna
inputfileTag=MC13TeV_2017_GGH2000toZZ2L2Nu
inputfileTag=MC13TeV_2017_GGToEE_lpair
inputfileTag=Data13TeV_2017F_MuonEG
inputfileTag=MC13TeV_2017_GJets_HT400to600
#inputfileTag=Data13TeV_2017B_DoubleMuon
inputfileTag=Data13TeV_2017B_ZeroBias
inputfileTESTSEL=${eosdir}/${inputfileTag}/Chunk_0_ext0.root
lumi=41833
ppsLumi=37500
lumiUnc=0.025


RED='\e[31m'
NC='\e[0m'
case $WHAT in

    TESTSYNCH )
        
        python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/scripts/runLocalAnalysis.py \
            -i /store/cmst3/user/psilva/ExclusiveAna/synch/Data13TeV_2017_DoubleMuon_synch.root \
            -o testsynch.root --genWeights genweights_${githash}.root \
            --njobs 1 -q local --debug \
            --era era2017 -m ExclusiveZX::RunExclusiveZX --ch 0 --runSysts;

        ;;

    TESTSEL )
        python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/scripts/runLocalAnalysis.py \
            -i ${inputfileTESTSEL} --tag ${inputfileTag} \
            -o testsel.root --genWeights genweights_${githash}.root \
            --njobs 1 -q local --debug \
            --era era2017 -m ExclusiveZX::RunExclusiveZX --ch 0 --runSysts;
        ;;

    SEL )
        baseOpt="-i ${eosdir} --genWeights genweights_${githash}.root"
        baseOpt="${baseOpt} -o ${outdir} -q ${queue} --era era2017 -m ExclusiveZX::RunExclusiveZX --ch 0 --runSysts"
        #baseOpt="${baseOpt} --exactonly"        
	python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/scripts/runLocalAnalysis.py ${baseOpt} \
            --only ${samples_json},${zx_samples_json},${zbias_samples_json};
	;;

    MERGESEL )
	mergeOutputs.py /eos/cms/${outdir} True;
	;;

    PLOTSEL )
        lumiSpecs="--lumiSpecs lpta:2642"
        kFactorList="--procSF #gamma+jets:1.4"
	commonOpts="-i /eos/cms/${outdir} --puNormSF puwgtctr -l ${lumi} --mcUnc ${lumiUnc} ${kFactorList} ${lumiSpecs}"
	python scripts/plotter.py ${commonOpts} -j ${samples_json}    -O plots/sel --only mboson,mtboson,pt,eta,met,jets,nvtx,ratevsrun --saveLog; 
        python scripts/plotter.py ${commonOpts} -j ${samples_json}    --rawYields --silent --only gen -O plots/zx_sel -o bkg_plotter.root ; 
	python scripts/plotter.py ${commonOpts} -j ${zx_samples_json} --rawYields --silent --only gen -O plots/zx_sel;
        python test/analysis/pps/computeDileptonSelEfficiency.py 
        mv *.{png,pdf} plots/zx_sel/
        mv effsummary* plots/
	;;

    WWWSEL )
	mkdir -p ${wwwdir}/presel
	cp plots/sel/*.{png,pdf} ${wwwdir}/presel
	cp plots/zx_sel/*.{png,pdf} ${wwwdir}/presel
	cp $CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/index.php ${wwwdir}/presel
	;;

    TRAINPUDISCR )
        echo "Please remember to use a >10_3_X release for this step"

        commonOpts="--trainFrac 0.4  --RPout test/analysis/pps/golden_noRP.json -o /eos/cms/${outdir}/train_results"
        #python test/analysis/pps/trainPUdiscriminators.py ${commonOpts} -s "isZ && bosonpt<10 && trainCat>=0" 
        python test/analysis/pps/trainPUdiscriminators.py ${commonOpts} -s "hasZBTrigger && trainCat>=0" --zeroBiasTrain

        ;;

    RUNPRED )
        predin=/eos/cms/${outdir}/Chunks
        predout=/eos/cms/${outdir}/Chunks/pudiscr 
        condor_prep=runpred_condor.sub
        echo "executable  = ${CMSSW_BASE}/src/TopLJets2015/TopAnalysis/test/analysis/pps/wrapPUDiscrTrain.sh" > $condor_prep
        echo "output      = ${condor_prep}.out" >> $condor_prep
        echo "error       = ${condor_prep}.err" >> $condor_prep
        echo "log         = ${condor_prep}.log" >> $condor_prep
        echo "arguments   = ${predout} \$(chunk)" >> $condor_prep
        echo "queue chunk matching (${predin}/*.root)" >> $condor_prep
        condor_submit $condor_prep
        ;;

    PREPAREANA )       
        step=0
        predin=/eos/cms/${outdir}/Chunks
        predout=/eos/cms/${outdir}/mixing
        condor_prep=runana_condor.sub
        echo "executable  = ${CMSSW_BASE}/src/TopLJets2015/TopAnalysis/test/analysis/pps/wrapAnalysis.sh" > $condor_prep
        echo "output      = ${condor_prep}.out" >> $condor_prep
        echo "error       = ${condor_prep}.err" >> $condor_prep
        echo "log         = ${condor_prep}.log" >> $condor_prep
        echo "arguments   = ${step} ${predout} ${predin} \$(chunk)" >> $condor_prep
        echo "queue chunk matching (${predin}/Data*.root)" >> $condor_prep
        condor_submit $condor_prep
        
        #python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/runExclusiveAnalysis.py --step 0 --jobs 8 \
        #    --json ${samples_json} --RPout ${RPout_json} -o ${predout} -i ${predin};

        ;;

    COLLECTMIX )
        python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/collectEventsForMixing.py /eos/cms/${outdir}
        ;;

    ANA )
        step=1
        predin=/eos/cms/${outdir}/Chunks
        predout=/eos/cms/${outdir}/analysis
        condor_prep=runana_condor.sub
        mix_file=/eos/cms/${outdir}/mixing/mixbank.pck
        echo "executable  = ${CMSSW_BASE}/src/TopLJets2015/TopAnalysis/test/analysis/pps/wrapAnalysis.sh" > $condor_prep
        echo "output      = ${condor_prep}.out" >> $condor_prep
        echo "error       = ${condor_prep}.err" >> $condor_prep
        echo "log         = ${condor_prep}.log" >> $condor_prep
        echo "arguments   = ${step} ${predout} ${predin} \$(chunk)" ${mix_file} >> $condor_prep
        echo "queue chunk matching (${predin}/*.root)" >> $condor_prep
        condor_submit $condor_prep

        #run locally
        #python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/runExclusiveAnalysis.py --step 1 --jobs 8 \
        #    --json ${samples_json} --RPout ${RPout_json} -o ${predout} --mix ${mix_file} -i ${predin};
        
        ;;

    ANASIG )
        
        python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/runExclusiveAnalysis.py --step 1 --jobs 8 \
            --json ${signal_json} --RPout ${RPout_json} --mix /eos/cms/${outdir}/analysis/mixbank.pck \
            -i /eos/cms/${outdir}/Chunks -o /eos/cms/${outdir}/analysis

        ;;

    MERGEANA )
        mergeOutputs.py /eos/cms/${outdir}/analysis;
        ;;

    PLOTANA )

        lptalumi=2642
        lumiSpecs="lpta:${lptalumi},lptahpur:${lptalumi},lptahpur120:${lptalumi},lptahpur130:${lptalumi},lptahpur140:${lptalumi},lptahpur150:${lptalumi}"
        lumiSpecs="${lumiSpecs},lptahpur120neg:${lptalumi},lptahpur130neg:${lptalumi},lptahpur140neg:${lptalumi},lptahpur150neg:${lptalumi},lptahpur120pos:${lptalumi},lptahpur130pos:${lptalumi},lptahpur140pos:${lptalumi},lptahpur150pos:${lptalumi}"

	baseOpts="-i /eos/cms/${outdir}/analysis --lumiSpecs ${lumiSpecs} --procSF #gamma+jets:1.4 -l ${ppsLumi} --mcUnc ${lumiUnc} ${lumiSpecs} ${kFactorList}"
        
        plots=xangle_ee,xangle_mm,xangle_eeZ,xangle_mmZ,xangle_eehptZ,xangle_mmhptZ
        commonOpts="${baseOpts} -j ${zx_samples_json} -O plots/analysis/zx_yields" 
        #python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/scripts/plotter.py ${commonOpts} --only ${plots} --strictOnly --saveTeX --rebin 4;

        
        plots=xangle_eeZ,xangle_mmZ,xangle_eehptZ,xangle_mmhptZ,xangle_eehptZelpphighPur,xangle_mmhptZelpphighPur
        commonOpts="${baseOpts} -j ${samples_json}" # --normToData"
        #python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/scripts/plotter.py ${commonOpts} --only ${plots} --strictOnly --saveTeX --rebin 4;
                
        plots=mll_ee,mll_mm,mll_em,ptll_eeZ,ptll_mmZ,ptll_em,ptll_lpta,ptll_hpta
        plots=${plots},l1pt_eeZ,l1pt_mmZ,l1pt_em,l2pt_eeZ,l2pt_mmZ,l2pt_em
        plots=${plots},acopl_eeZ,acopl_mmZ,acopl_em,l1eta_eeZ,l1eta_mmZ,l1eta_em,l2eta_eeZ,l2eta_mmZ,l2eta_em
        plots=${plots},acopl_eeZelpphighPur140,acopl_mmZelpphighPur140,ptll_eeZelpphighPur140,ptll_mmZelpphighPur140
        plots=${plots},l1pt_eeZelpphighPur140,l1pt_mmZelpphighPur140,l2pt_eeZelpphighPur140,l2pt_mmZelpphighPur140
        plots=${plots},nvtx_eeZ,nvtx_mmZ,nvtx_em,xangle_eeZ,xangle_mmZ,xangle_em,nvtx_lpta,nvtx_hpta,xangle_lpta,xangle_lpta
        #python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/scripts/plotter.py ${commonOpts} --only ${plots} --strictOnly --signalJson ${plot_signal_json} --saveLog --normToData;


        plots=""
        for c in eeZhpur mmZhpur emhpur lptahpur hptahpur; do
            for d in xangle ntk; do
                for s in pos neg; do
                    plots="${plots},${d}_${c}${x}${s}"
                done
            done
            for x in 120 130 140 150; do
                for d in rho mpp ypp mpp2d ypp2d mmass nextramu ptll yll; do
                    plots="${plots},${d}_${c}${x}"
                done
                for d in csi csi2d; do
                    for s in pos neg; do
                        plots="${plots},${d}_${c}${x}${s}"
                    done
                done
            done
        done
        python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/scripts/plotter.py ${commonOpts} --only ${plots} --strictOnly --signalJson ${plot_signal_json} --saveLog; # --normToData;
        
#python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/scripts/plotter.py ${commonOpts} --only ${plots} --strictOnly --signalJson ${signal_json} --saveLog;
        
        #python $CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/analysis/pps/compareBackgroundEstimation.py plots/analysis/plots/plotter.root plots/analysis/plots;
        ;;

    WWWANA )
        mkdir -p ${wwwdir}/ana
        cp /eos/cms/${outdir}/analysis/plots/*.{png,pdf,dat} ${wwwdir}/ana
        cp $CMSSW_BASE/src/TopLJets2015/TopAnalysis/test/index.php ${wwwdir}/ana
        ;;

    OPTIMANA )
        for i in 1000 1200 1400; do
            python test/analysis/pps/optimizeSR.py ${i}; 
        done
        python test/analysis/pps/plotLimits.py 1000=optimresults_1000.pck,1200=optimresults_1200.pck,1400=optimresults_1400.pck
        python test//analysis/pps/compareOptimResults.py
        ;;

esac