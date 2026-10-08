#!/bin/bash
# Script de démarrage FlashShop pour une image Debian 12.
# À passer au template avec l'argument metadata_startup_script et la fonction file() de Terraform.
# Il installe une page HTTP sur le port 8080 avec le Python déjà présent sur l'image :
# aucun téléchargement n'est nécessaire. Il peut être rejoué sans risque à chaque démarrage.
#
# Routes : /               page qui montre quelle instance répond, avec un petit générateur de charge
#          /api/instance   identité de l'instance qui a répondu (JSON)
#          /api/travail    même chose après un calcul de ms millisecondes, pour charger le CPU
#          /api/deploiement  ce que l'instance constate de son propre déploiement
#          /healthz        pour les health checks du Load Balancer et de l'autohealing
set -euo pipefail

cat > /opt/flashshop.py <<'PY'
import ipaddress
import itertools
import json
import os
import socket
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def metadata(path, default):
    request = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/" + path,
        headers={"Metadata-Flavor": "Google"},
    )
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            return response.read().decode()
    except Exception:
        return default


# Sur Compute Engine, tout vient du serveur de métadonnées. En local, des variables d'environnement
# prennent le relais. La version vient de la métadonnée app-version du template.
SUR_GCE = not os.environ.get("INSTANCE_NAME") and metadata("instance/id", None) is not None
INSTANCE = os.environ.get("INSTANCE_NAME") or metadata("instance/name", socket.gethostname())
ZONE = (os.environ.get("ZONE") or metadata("instance/zone", "inconnue")).rsplit("/", 1)[-1]
VERSION = os.environ.get("APP_VERSION") or metadata("instance/attributes/app-version", "dev")
EXTERNE = metadata("instance/network-interfaces/0/access-configs/0/external-ip", None) if SUR_GCE else None
CREE_PAR = metadata("instance/attributes/created-by", "") if SUR_GCE else ""
DEMARRAGE = time.time()
REQUETES = itertools.count(1)

# Démo publique : charge plafonnée, calcul court et nombre de requêtes limité par seconde.
DEMO = os.environ.get("DEMO_PUBLIQUE") == "true"
CHARGE_MAX = int(os.environ.get("CHARGE_MAX", "5" if DEMO else "80"))
TRAVAIL_MAX_MS = 20 if DEMO else 500

# Plages documentées des sondes de health check des Load Balancers Google.
PLAGES_SONDES = [ipaddress.ip_network("35.191.0.0/16"), ipaddress.ip_network("130.211.0.0/22")]
etat = {"sondes": 0, "derniere_sonde": 0.0, "sortie": None}
verrou = threading.Lock()


def tester_sortie():
    # Sans IP externe, une sortie qui réussit passe forcément par Cloud NAT.
    while True:
        try:
            socket.create_connection(("deb.debian.org", 443), timeout=3).close()
            etat["sortie"] = True
        except OSError:
            etat["sortie"] = False
        time.sleep(300)


class Limiteur:
    def __init__(self, par_seconde):
        self.capacite = self.jetons = par_seconde
        self.maj = time.monotonic()
        self.verrou = threading.Lock()

    def autoriser(self):
        with self.verrou:
            maintenant = time.monotonic()
            self.jetons = min(self.capacite, self.jetons + (maintenant - self.maj) * self.capacite)
            self.maj = maintenant
            if self.jetons < 1:
                return False
            self.jetons -= 1
            return True


LIMITEUR = Limiteur(30) if DEMO else None


def bloc(id, nom, etat_bloc, detail="", preuve=""):
    return {"id": id, "nom": nom, "etat": etat_bloc, "detail": detail, "preuve": preuve}


def carte():
    if not SUR_GCE:
        blocs = [
            bloc("vm", "VM du groupe", "simule", f"conteneur {INSTANCE}, zone {ZONE}, version {VERSION}"),
            bloc("ip", "Adresse des VM", "simule", "les VM du compose ne publient aucun port"),
            bloc("mig", "Groupe d’instances", "simule", "trois conteneurs du compose, un par zone"),
            bloc("sondes", "Health checks", "simule", "nginx ne sonde pas les VM en local"),
            bloc("nat", "Sortie Internet", "simule", "sortie directe du conteneur"),
        ]
    else:
        blocs = [bloc("vm", "VM du groupe", "ok", f"instance {INSTANCE}, zone {ZONE}, version {VERSION}", "serveur de métadonnées")]
        blocs.append(bloc("ip", "Adresse des VM", "alerte", f"cette VM a une IP externe : {EXTERNE}", "access-config présent")
                     if EXTERNE else bloc("ip", "Adresse des VM", "ok", "aucune IP externe sur cette VM", "aucun access-config dans les métadonnées"))
        if "/instanceGroupManagers/" in CREE_PAR:
            genre = "MIG régional" if "/regions/" in CREE_PAR else "MIG zonal"
            blocs.append(bloc("mig", "Groupe d’instances", "ok", f"{genre} {CREE_PAR.rsplit('/', 1)[-1]}", CREE_PAR))
        else:
            blocs.append(bloc("mig", "Groupe d’instances", "inconnu", "cette VM n’a pas été créée par un MIG"))
        with verrou:
            sondes, derniere = etat["sondes"], etat["derniere_sonde"]
        blocs.append(bloc("sondes", "Health checks", "ok", f"{sondes} sonde(s) reçue(s) depuis les plages Google, la dernière il y a {int(time.time() - derniere)} s", "35.191.0.0/16 et 130.211.0.0/22")
                     if sondes else bloc("sondes", "Health checks", "inconnu", "aucune sonde reçue : health check créé, pare-feu ouvert aux plages des sondes ?"))
        if etat["sortie"] is None:
            blocs.append(bloc("nat", "Sortie Internet", "inconnu", "test de sortie en cours"))
        elif etat["sortie"] and not EXTERNE:
            blocs.append(bloc("nat", "Sortie par Cloud NAT", "ok", "sortie Internet possible sans IP externe", "connexion à deb.debian.org:443 réussie"))
        elif etat["sortie"]:
            blocs.append(bloc("nat", "Sortie Internet", "ok", "sortie par l’IP externe de la VM, pas par NAT", "connexion à deb.debian.org:443 réussie"))
        else:
            blocs.append(bloc("nat", "Sortie Internet", "inconnu", "aucune sortie Internet : Cloud Router et NAT en place ?", "connexion à deb.debian.org:443 impossible"))
    blocs += [
        bloc("armor", "Cloud Armor", "manuel", "règle et logs de décision : à montrer dans la console"),
        bloc("autoscaler", "Autoscaler", "manuel", "décisions de capacité : à montrer dans le MIG et Monitoring"),
        bloc("obs", "Monitoring et alertes", "manuel", "dashboard et alertes : à montrer dans la console"),
    ]
    return {"plateforme": "Compute Engine" if SUR_GCE else "local", "blocs": blocs}


PAGE = r"""<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>FlashShop, démonstrateur</title>
<style>
:root{--ink:#0f172a;--muted:#5b6575;--line:#e2e8f0;--soft:#f6f8fa;--night:#0b1220;--accent:#e0473a;--ok:#0f8a4f;--warn:#b45309;--err:#c5221f;--mono:ui-monospace,"SF Mono",Menlo,Consolas,monospace}
*{box-sizing:border-box}body{margin:0;background:var(--soft);color:#1e293b;font:15px/1.6 ui-sans-serif,-apple-system,"Segoe UI",Roboto,Arial,sans-serif}
header{background:var(--night);color:#fff}header div{max-width:1100px;margin:auto;padding:12px 24px;display:flex;gap:12px;align-items:center}
.mark{width:10px;height:10px;border-radius:2px;background:var(--accent)}.brand{font:600 15px/1 var(--mono)}#env{margin-left:auto;font:12px/1.4 var(--mono);color:#94a3b8}
main{max-width:1100px;margin:auto;padding:24px;display:grid;gap:16px}h1{margin:0;font-size:26px;color:var(--ink)}.lead{color:var(--muted);margin:4px 0 0}
.panel{background:#fff;border:1px solid var(--line);border-radius:8px;padding:18px}.panel h2{margin:0 0 12px;font:600 12px/1.4 var(--mono);text-transform:uppercase;letter-spacing:.08em;color:var(--muted)}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px}.stat{border:1px solid var(--line);border-radius:6px;padding:10px 12px;background:#fff}
.stat>span{display:block;font:11px/1.4 var(--mono);text-transform:uppercase;letter-spacing:.06em;color:var(--muted)}.stat strong{font:600 20px/1.35 var(--mono);color:var(--ink)}
button{font:500 13px/1.4 var(--mono);padding:7px 12px;border-radius:5px;border:1px solid #c4ceda;background:#fff;cursor:pointer}button.on{border-color:var(--accent);box-shadow:inset 0 0 0 1px var(--accent)}
.row{display:flex;flex-wrap:wrap;gap:8px;align-items:center}.muted{color:var(--muted);font-size:13px}
.barre{display:grid;grid-template-columns:minmax(150px,240px) 1fr 70px;gap:10px;align-items:center;margin:8px 0;font:13px/1.4 var(--mono)}
.barre .fond{height:14px;background:#eef1f4;border-radius:3px;overflow:hidden}.barre .fond span{display:block;height:100%}.barre.muette{opacity:.4}
#cases{display:flex;flex-wrap:wrap;gap:3px}#cases i{width:12px;height:12px;border-radius:2px;display:block}
.badge{display:inline-block;font:600 11px/1.6 var(--mono);padding:1px 7px;border-radius:4px;background:var(--soft);border:1px solid var(--line);color:var(--muted)}
.badge.ok{color:var(--ok);border-color:#b7e1c7;background:#effaf3}.badge.warn{color:var(--warn);border-color:#f3d7a7;background:#fff8ec}.badge.err{color:var(--err);border-color:#f5c2bf;background:#fef3f2}.badge.sim{color:#4f46e5;border-color:#c7d2fe;background:#eef2ff}
.carte{display:grid;gap:12px}.resume{font:13px/1.4 var(--mono);color:var(--muted)}
.rangee{display:grid;grid-template-columns:110px repeat(auto-fit,minmax(170px,1fr));gap:10px}.rangee>span{font:600 11px/1.4 var(--mono);text-transform:uppercase;letter-spacing:.06em;color:var(--muted);padding-top:12px}
.bloc{border:1px solid var(--line);border-left:4px solid #cbd5e1;border-radius:6px;padding:10px 12px;background:#fff;min-width:0}
.bloc strong{display:block;color:var(--ink);margin:6px 0 2px;font-size:14px}.bloc p{margin:0;font-size:13px;line-height:1.45;color:var(--muted)}.bloc code{display:block;margin-top:6px;font:11px/1.4 var(--mono);color:var(--muted);overflow-wrap:anywhere}
etat-inconnu{border-style:dashed;border-left-style:solid}.etat-manuel{border-style:dotted;border-left-style:solid;background:var(--soft)}.etat-simule{border-left-color:#6366f1;background:#f7f7ff}
@media(max-width:760px){.rangee{grid-template-columns:1fr}.rangee>span{padding-top:4px}}.etat-ok{border-left-color:var(--ok);background:#f5fbf7}.etat-alerte{border-left-color:var(--warn);background:#fffaf0}.etat-echec{border-left-color:var(--err);background:#fff6f5}
.
</style></head><body>
<header><div><span class="mark"></span><span class="brand">FlashShop</span><span id="env">...</span></div></header>
<main>
<div><h1>Qui répond derrière le Load Balancer ?</h1><p class="lead">Chaque requête passe par le Load Balancer, qui choisit une instance du MIG. Arrêtez le service sur une VM et regardez sa barre s’arrêter.</p></div>
<section class="panel"><h2>Carte du déploiement</h2><div class="carte" id="carte"><p class="muted">Analyse en cours...</p></div></section>
<div class="stats"><div class="stat"><span>Requêtes</span><strong id="n">0</strong></div><div class="stat"><span>Erreurs</span><strong id="e">0</strong></div><div class="stat"><span>Latence p50</span><strong id="p50">...</strong></div><div class="stat"><span>Latence p95</span><strong id="p95">...</strong></div></div>
<section class="panel"><h2>Charge</h2>
<div class="row"><button data-rate="1" class="on">Observer, 1 req/s</button><button data-rate="5">5 req/s</button><button data-rate="10">10 req/s</button><button data-rate="20">20 req/s</button><button data-rate="80">80 req/s</button><button data-rate="0">Arrêter</button>
<label class="muted"><input type="checkbox" id="cpu"> avec du calcul côté serveur</label></div>
<p class="muted" id="minuteur">Les paliers de charge s’arrêtent seuls après 60 secondes. Ne dépassez pas la capacité convenue avec le formateur.</p></section>
<section class="panel"><h2>Répartition entre les instances</h2><div id="barres"></div></section>
<section class="panel"><h2>Dernières réponses</h2><div id="cases"></div><p class="muted">Une case par réponse, de la couleur de l’instance. En rouge : une erreur ou un délai dépassé.</p></section>
</main>
<script>
const $=s=>document.querySelector(s);const vues=new Map();const latences=[];const cases=[];let n=0,erreurs=0,minuterie=null,fin=0,via=null,plateforme=null;
const couleur=id=>'hsl('+([...id].reduce((h,c)=>(h*31+c.charCodeAt(0))%997,7)*137.5)%360+' 70% 50%)';
async function requete(){n++;const t0=performance.now();const url=$('#cpu').checked?'/api/travail?ms=50':'/api/instance';
try{const r=await fetch(url,{cache:'no-store',signal:AbortSignal.timeout(3000)});if(!r.ok)throw new Error(r.status);via=r.headers.get('via')||via;const d=await r.json();
const ms=performance.now()-t0;latences.push(ms);if(latences.length>200)latences.shift();
const v=vues.get(d.instance)||{zone:d.zone,version:d.version,n:0};v.n++;v.vu=Date.now();v.version=d.version;vues.set(d.instance,v);cases.push(couleur(d.instance));}
catch(e){erreurs++;cases.push('var(--err)');}if(cases.length>150)cases.shift();}
function centile(p){if(!latences.length)return'...';const t=[...latences].sort((a,b)=>a-b);return Math.round(t[Math.min(t.length-1,Math.floor(p*t.length))])+' ms';}
function dessiner(){$('#n').textContent=n;$('#e').textContent=erreurs;$('#p50').textContent=centile(.5);$('#p95').textContent=centile(.95);
const total=[...vues.values()].reduce((s,v)=>s+v.n,0)||1;$('#barres').replaceChildren(...[...vues.entries()].sort().map(([id,v])=>{const d=document.createElement('div');
d.className='barre'+(Date.now()-v.vu>5000?' muette':'');d.innerHTML='<span></span><span class="fond"><span></span></span><span></span>';d.children[0].textContent=id+' / '+v.zone+' / '+v.version;
d.children[1].firstChild.style.width=(v.n/total*100)+'%';d.children[1].firstChild.style.background=couleur(id);d.children[2].textContent=v.n;return d;}));
$('#cases').replaceChildren(...cases.map(c=>{const i=document.createElement('i');i.style.background=c;return i;}));
if(fin){const reste=Math.max(0,Math.round((fin-Date.now())/1000));$('#minuteur').textContent='Palier en cours, encore '+reste+' s.';if(!reste)regler(1);}}
function regler(rate){clearInterval(minuterie);minuterie=null;fin=0;document.querySelectorAll('button[data-rate]').forEach(b=>b.classList.toggle('on',Number(b.dataset.rate)===rate));
if(rate>0){const step=Math.max(20,1000/rate);const batch=Math.max(1,Math.round(rate*step/1000));minuterie=setInterval(()=>{for(let i=0;i<batch;i++)requete();},step);}if(rate>1)fin=Date.now()+60000;else $('#minuteur').textContent='Les paliers de charge s’arrêtent seuls après 60 secondes.';}
document.querySelectorAll('button[data-rate]').forEach(b=>b.addEventListener('click',()=>regler(Number(b.dataset.rate))));
const etats={ok:['prouvé','ok'],alerte:['à revoir','warn'],echec:['en échec','err'],inconnu:['pas encore détecté',''],manuel:['à prouver vous-même',''],simule:['simulé en local','sim']};
const bloc=(id,nom,etat,detail='',preuve='')=>({id,nom,etat,detail,preuve});
async function carte(){let s;try{s=await(await fetch('/api/deploiement',{cache:'no-store'})).json();}catch{return;}
const local=s.plateforme==='local';const blocs=[...s.blocs];const zones=new Set([...vues.values()].map(v=>v.zone));
blocs.push(local?bloc('lb','Load Balancer','simule','nginx, local/lb.conf'):via&&/google/i.test(via)?bloc('lb','Load Balancer','ok','les réponses passent par un Load Balancer Google','via: '+via):bloc('lb','Load Balancer','inconnu','aucun en-tête Via de Google : la page passe-t-elle par le Load Balancer ?'));
const z=[...zones].sort().join(', ');blocs.push(zones.size>1?bloc('zones','Répartition entre zones',local?'simule':'ok','réponses venues de '+zones.size+' zones et '+vues.size+' instances',z):bloc('zones','Répartition entre zones',local?'simule':'inconnu',zones.size?'une seule zone vue pour l’instant : '+z:'en attente de réponses'));
const rangees=[['Entrée',['lb','armor']],['Flotte',['mig','zones','vm','ip']],['Santé',['sondes']],['Sorties',['nat']],['Exploitation',['autoscaler','obs']]];
const parId=new Map(blocs.map(b=>[b.id,b]));const lignes=rangees.map(([titre,ids])=>{const r=document.createElement('div');r.className='rangee';const t=document.createElement('span');t.textContent=titre;r.append(t);
for(const id of ids){const b=parId.get(id);if(!b)continue;const[texte,classe]=etats[b.etat]||etats.inconnu;const c=document.createElement('div');c.className='bloc etat-'+b.etat;
c.innerHTML='<span class="badge"></span><strong></strong><p></p><code></code>';c.children[0].className='badge '+classe;c.children[0].textContent=texte;c.children[1].textContent=b.nom;c.children[2].textContent=b.detail;
if(b.preuve)c.children[3].textContent=b.preuve;else c.children[3].remove();r.append(c);}return r;});
const det=blocs.filter(b=>b.etat!=='manuel');const ok=det.filter(b=>b.etat==='ok').length;const resume=document.createElement('p');resume.className='resume';
resume.textContent=det.every(b=>b.etat==='simule')?'En local, tous les blocs sont simulés. Une fois déployée sur GCP, la carte s’allume bloc par bloc.':ok+' bloc(s) prouvé(s) sur '+det.length+' détectables.';
$('#carte').replaceChildren(resume,...lignes);}
fetch('/api/instance',{cache:'no-store'}).then(r=>r.json()).then(d=>{$('#env').textContent='page servie par '+d.instance+' / '+d.zone+' / '+d.version;
document.querySelectorAll('button[data-rate]').forEach(b=>{if(Number(b.dataset.rate)>d.charge_max)b.remove();});});
regler(1);setInterval(dessiner,500);carte();setInterval(carte,10000);
</script></body></html>
""".encode()


class Handler(BaseHTTPRequestHandler):
    def repondre(self, status, body, kind):
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def json(self, contenu, status=200):
        self.repondre(status, json.dumps(contenu).encode() + b"\n", "application/json; charset=utf-8")

    def identite(self, **extra):
        return {"instance": INSTANCE, "zone": ZONE, "version": VERSION, "depuis_s": int(time.time() - DEMARRAGE),
                "requetes": next(REQUETES), "charge_max": CHARGE_MAX, **extra}

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        if url.path == "/healthz":
            try:
                source = ipaddress.ip_address(self.client_address[0])
                if any(source in plage for plage in PLAGES_SONDES):
                    with verrou:
                        etat["sondes"] += 1
                        etat["derniere_sonde"] = time.time()
            except ValueError:
                pass
            return self.repondre(200, b"ok\n", "text/plain; charset=utf-8")
        if url.path == "/":
            return self.repondre(200, PAGE, "text/html; charset=utf-8")
        if url.path.startswith("/api/") and LIMITEUR and not LIMITEUR.autoriser():
            return self.json({"erreur": "trop de requêtes pour la démo publique"}, 429)
        if url.path == "/api/instance":
            return self.json(self.identite())
        if url.path == "/api/travail":
            try:
                ms = min(TRAVAIL_MAX_MS, max(0, int(urllib.parse.parse_qs(url.query).get("ms", ["50"])[0])))
            except ValueError:
                ms = 20
            fin = time.perf_counter() + ms / 1000
            while time.perf_counter() < fin:
                pass
            return self.json(self.identite(travail_ms=ms))
        if url.path == "/api/deploiement":
            return self.json(carte())
        self.send_error(404)

    def log_message(self, *args):
        pass  # les journaux du Load Balancer suffisent


threading.Thread(target=tester_sortie, daemon=True).start()
serveur = ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler)
print(f"FlashShop prêt sur le port {serveur.server_address[1]}, instance {INSTANCE}", flush=True)
serveur.serve_forever()
PY

cat > /etc/systemd/system/flashshop.service <<'UNIT'
[Unit]
Description=FlashShop, page de démonstration
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 /opt/flashshop.py
Restart=on-failure
DynamicUser=yes

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable flashshop.service
systemctl restart flashshop.service
