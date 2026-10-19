EXTRA_PRESCRIP.up('upv',r,t) = 0 ;
EXTRA_PRESCRIP.up('wind-ons',r,t) = 0 ;
EXTRA_PRESCRIP.up('wind-ofs',r,t) = 0 ;
EXTRA_PRESCRIP.up('pvb',r,t) = 0 ;
EXTRA_PRESCRIP.up('battery_li',r,t) = 0 ;
EXTRA_PRESCRIP_ENERGY.up('battery_li',r,t) = 0 ;

set battery_li_prescription(r,t) "battery_li region-years with prescribed power or energy capacity" ;
battery_li_prescription(r,t)$[
       sum{pcat$prescriptivelink(pcat,'battery_li'),
           noncumulative_prescriptions(pcat,r,t)}
    or sum{pcat$prescriptivelink(pcat,'battery_li'),
           noncumulative_prescriptions_energy(pcat,r,t)}
] = yes ;

valinv('battery_li',v,r,t)$[not battery_li_prescription(r,t)] = no ;
inv_cond('battery_li',v,r,t,tt)$[not battery_li_prescription(r,tt)] = no ;
m_refurb_cond('battery_li',v,r,t,tt)$[not battery_li_prescription(r,tt)] = no ;

INV.up('battery_li',v,r,t)$[not battery_li_prescription(r,t)] = 0 ;
INV_ENERGY.up('battery_li',v,r,t)$[not battery_li_prescription(r,t)] = 0 ;

valinv_init('battery_li',v,r,t) = valinv('battery_li',v,r,t) ;
valinv_irt(i,r,t) = sum{v, valinv(i,v,r,t) } ;
valinv_tg(st,tg,t) = no ;
valinv_tg(st,tg,t)$sum{(i,r)$[tg_i(tg,i)$r_st(r,st)], valinv_irt(i,r,t) } = yes ;
