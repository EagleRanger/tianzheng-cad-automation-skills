"""Read-only native LINE/ARC split into inside/outside bulged HATCH parameters.

Uses the existing isolated core-console reader; never uses the production CAD
session or writes DWG. Unsupported curves/topology return explicit exceptions.
"""
import argparse,json
from cad_geometry_read import run

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for key in ('environment','request','workdir'):p.add_argument('--'+key,required=True)
    a=p.parse_args()
    print(json.dumps(run(a.environment,a.request,a.workdir,operation='hatch_split'),ensure_ascii=False,indent=2))
