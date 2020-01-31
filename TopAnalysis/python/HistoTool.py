import ROOT

class HistoTool:

    def __init__(self):
        self.histos={}

    def add(self,h):

        """ add new histogram (the name is the key in the dict) """

        self.histos[h.GetName()]={'inc':h}
        h.Sumw2()
        h.SetDirectory(0)

    def get(self,k,cat='inc'):

        """ returns an histogram """

        return self.histos[k][cat] if k in self.histos and cat in self.histos[k] else None
        
    def fill(self,val,key,cats,pfix=None):

        """if available fills the histo, otherwise it starts a new one"""

        if not key in self.histos: return
        for cat in cats:
            if pfix: cat=cat+pfix
            if not cat in self.histos[key]:
                self.histos[key][cat]=self.histos[key]['inc'].Clone('%s_%s'%(key,cat))
                self.histos[key][cat].SetDirectory(0)
                self.histos[key][cat].Reset('ICE')
            self.histos[key][cat].Fill(*val)
            

    def writeToFile(self,fOut):

        """dumps all histograms to a file"""
        
        if isinstance(fOut,str):
            fOut=ROOT.TFile.Open(fOut,'RECREATE')
        fOut.cd()
        
        for name in self.histos:
            for cat in self.histos[name]:
                if self.histos[name][cat].GetEntries()==0 : 
                    self.histos[name][cat].Delete()
                    continue
                self.histos[name][cat].SetDirectory(fOut)
                self.histos[name][cat].Write()
        fOut.Close()
