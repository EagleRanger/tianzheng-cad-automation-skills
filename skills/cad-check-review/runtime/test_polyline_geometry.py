import copy,json,subprocess,unittest
from unittest.mock import patch
import cad_session_client as c
from cad_runtime import bound_edits as bridge
from test_bound_cad_edits import BoundEditTests

class GeometryProtocolTests(unittest.TestCase):
    setUp=BoundEditTests.setUp
    put=BoundEditTests.put
    probe=BoundEditTests.probe
    release=BoundEditTests.release
    def geometry_params(self,kind):
        t={'handle':'A','type':'AcDbPolyline','layer':'0','bounds':[0,0,10,1]}
        return {'edits':[{'target':t,'expected_closed':False,'vertices':[[0,0,.2,.1,.2],[10,0,0,.2,.1]]}]} if kind=='polyline_edit' else {'offsets':[{'target':t,'distance':-.25}]}
    def test_geometry_reuses_saved_bound_queue_without_external_source(self):
        for kind in ('polyline_edit','polyline_offset'):
            with patch.object(bridge,'verified_release',return_value=self.release()),patch.object(bridge.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
                out=c.submit(self.binding,kind,self.geometry_params(kind),kind,probe=self.probe)
            self.assertEqual(out['transport'],'bound_native_extension')
            job=c.read(self.folder/(kind+'.job.json'))
            self.assertIn('output',job)
            self.assertNotIn('source',job)
            self.assertFalse((self.folder/'request.json').exists())
            # Settle this fake request before trying the next independent kind.
            # Each iteration receives an independent fixture to avoid simulating native success.
            if kind=='polyline_edit':self.tearDown();self.setUp()
    def test_bad_geometry_fails_before_native_dispatch(self):
        for distance in (0,float('nan'),float('inf'),True):
            p=self.geometry_params('polyline_offset');p['offsets'][0]['distance']=distance
            with self.assertRaises(c.ClientError):c.validate('polyline_offset',p)
        for bad in ([[0,0,0],[1,1,0]],[[0,0,0,-1,0],[1,1,0,0,0]],[[0,0,0,0,0],[0,0,0,0,0]]):
            p=self.geometry_params('polyline_edit');p['edits'][0]['vertices']=bad
            with self.assertRaises(c.ClientError):c.validate('polyline_edit',p)
        p=self.geometry_params('polyline_edit');p['edits'].append(copy.deepcopy(p['edits'][0]))
        with self.assertRaises(c.ClientError):c.validate('polyline_edit',p)

if __name__=='__main__':unittest.main()
