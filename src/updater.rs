use crate::hbbs_http::create_http_client_with_url;
use hbb_common::{bail, config, log, ResultType};
use serde_derive::Deserialize;
use std::{
    io::Write,
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc::{channel, Receiver, Sender},
        Mutex,
    },
    time::{Duration, Instant},
};

enum UpdateMsg {
    CheckUpdate,
    Exit,
}

lazy_static::lazy_static! {
    static ref TX_MSG : Mutex<Sender<UpdateMsg>> = Mutex::new(start_auto_update_check());
}

static CONTROLLING_SESSION_COUNT: AtomicUsize = AtomicUsize::new(0);

const DUR_ONE_DAY: Duration = Duration::from_secs(60 * 60 * 24);

pub fn update_controlling_session_count(count: usize) {
    CONTROLLING_SESSION_COUNT.store(count, Ordering::SeqCst);
}

#[allow(dead_code)]
pub fn start_auto_update() {
    let _sender = TX_MSG.lock().unwrap();
}

#[allow(dead_code)]
pub fn manually_check_update() -> ResultType<()> {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::CheckUpdate)?;
    Ok(())
}

#[allow(dead_code)]
pub fn stop_auto_update() {
    let sender = TX_MSG.lock().unwrap();
    sender.send(UpdateMsg::Exit).unwrap_or_default();
}

#[inline]
fn has_no_active_conns() -> bool {
    let conns = crate::Connection::alive_conns();
    conns.is_empty() && has_no_controlling_conns()
}

#[cfg(any(not(target_os = "windows"), feature = "flutter"))]
fn has_no_controlling_conns() -> bool {
    CONTROLLING_SESSION_COUNT.load(Ordering::SeqCst) == 0
}

#[cfg(not(any(not(target_os = "windows"), feature = "flutter")))]
fn has_no_controlling_conns() -> bool {
    let app_exe = format!("{}.exe", crate::get_app_name().to_lowercase());
    for arg in [
        "--connect",
        "--play",
        "--file-transfer",
        "--view-camera",
        "--port-forward",
        "--rdp",
    ] {
        if !crate::platform::get_pids_of_process_with_first_arg(&app_exe, arg).is_empty() {
            return false;
        }
    }
    true
}

fn start_auto_update_check() -> Sender<UpdateMsg> {
    let (tx, rx) = channel();
    std::thread::spawn(move || start_auto_update_check_(rx));
    return tx;
}

fn start_auto_update_check_(rx_msg: Receiver<UpdateMsg>) {
    std::thread::sleep(Duration::from_secs(30));
    if let Err(e) = check_update(false) {
        log::error!("Error checking for updates: {}", e);
    }

    const MIN_INTERVAL: Duration = Duration::from_secs(60 * 10);
    const RETRY_INTERVAL: Duration = Duration::from_secs(60 * 30);
    let mut last_check_time = Instant::now();
    let mut check_interval = DUR_ONE_DAY;
    loop {
        let recv_res = rx_msg.recv_timeout(check_interval);
        match &recv_res {
            Ok(UpdateMsg::CheckUpdate) | Err(_) => {
                if last_check_time.elapsed() < MIN_INTERVAL {
                    // log::debug!("Update check skipped due to minimum interval.");
                    continue;
                }
                // Don't check update if there are alive connections.
                if !has_no_active_conns() {
                    check_interval = RETRY_INTERVAL;
                    continue;
                }
                if let Err(e) = check_update(matches!(recv_res, Ok(UpdateMsg::CheckUpdate))) {
                    log::error!("Error checking for updates: {}", e);
                    check_interval = RETRY_INTERVAL;
                } else {
                    last_check_time = Instant::now();
                    check_interval = DUR_ONE_DAY;
                }
            }
            Ok(UpdateMsg::Exit) => break,
        }
    }
}

// PCNET-IT: auto-update por manifesto ASSINADO servido pela VM console
// (connect.pcnet-it.com:82/update). O manifesto e' verificado com esta chave
// publica Ed25519 (a privada = segredo do CI UPDATE_SIGNING_SEED); so depois
// se baixa o instalador e se verifica o sha256 contra o manifesto assinado.
// Assim a integridade e' ponta-a-ponta e o transporte pode ser HTTP simples
// (TLS impossivel por DDNS + portas nao-standard).
const PCNET_UPDATE_BASE: &str = "http://connect.pcnet-it.com:82/update";
const PCNET_UPDATE_PK: [u8; 32] = [
    0x9e, 0x6e, 0xdb, 0x25, 0x49, 0xdb, 0x8f, 0x63, 0x7f, 0xc4, 0xb8, 0x00, 0x61, 0x56, 0xc9, 0xfa,
    0xb2, 0xb8, 0x58, 0xf5, 0x47, 0xcb, 0xb2, 0x0e, 0x01, 0x7f, 0xb8, 0xc5, 0x86, 0x4c, 0xa5, 0x53,
];

#[derive(Deserialize)]
struct PcnetUpdFile {
    platform: String,
    arch: String,
    kind: String,
    name: String,
    sha256: String,
}

#[derive(Deserialize)]
struct PcnetManifest {
    version: String,
    files: Vec<PcnetUpdFile>,
}

fn check_update(manually: bool) -> ResultType<()> {
    // PCNET-IT: ligado por defeito (opt-out). So desliga se allow-auto-update == "N".
    if !manually && config::Config::get_option(config::keys::OPTION_ALLOW_AUTO_UPDATE) == "N" {
        return Ok(());
    }

    // 1) buscar o manifesto e a assinatura destacada (mesmo host -> um so cliente).
    let manifest_url = format!("{}/manifest.json", PCNET_UPDATE_BASE);
    let sig_url = format!("{}/manifest.json.sig", PCNET_UPDATE_BASE);
    let client = create_http_client_with_url(&manifest_url);
    let manifest_bytes = client
        .get(&manifest_url)
        .send()?
        .error_for_status()?
        .bytes()?;
    let sig_b64 = client.get(&sig_url).send()?.error_for_status()?.text()?;

    // 2) verificar a assinatura Ed25519 com a chave publica embutida.
    {
        use hbb_common::base64::{engine::general_purpose::STANDARD, Engine as _};
        use hbb_common::sodiumoxide::crypto::sign;
        let sig_bytes = STANDARD.decode(sig_b64.trim())?;
        let Some(sig) = sign::Signature::from_slice(&sig_bytes) else {
            bail!("PCNET update: assinatura mal formada");
        };
        if !sign::verify_detached(&sig, &manifest_bytes, &sign::PublicKey(PCNET_UPDATE_PK)) {
            bail!("PCNET update: assinatura do manifesto invalida");
        }
    }

    let manifest: PcnetManifest = serde_json::from_slice(&manifest_bytes)?;
    let version = manifest.version.clone();
    if hbb_common::get_version_number(&version) <= hbb_common::get_version_number(crate::VERSION) {
        log::debug!("PCNET update: sem versao mais nova (manifesto {})", version);
        return Ok(());
    }
    if !has_no_active_conns() {
        return Ok(());
    }

    // 3) escolher o instalador para esta plataforma / arquitectura.
    let arch = std::env::consts::ARCH; // "x86_64" | "aarch64"
    #[cfg(target_os = "windows")]
    let update_msi = crate::platform::is_msi_installed().unwrap_or(false);
    #[cfg(target_os = "windows")]
    let (platform, kind) = ("windows", if update_msi { "msi" } else { "exe" });
    #[cfg(target_os = "macos")]
    let (platform, kind) = ("macos", "dmg");
    #[cfg(not(any(target_os = "windows", target_os = "macos")))]
    let (platform, kind) = ("linux", "deb");
    let Some(file) = manifest
        .files
        .into_iter()
        .find(|f| f.platform == platform && f.arch == arch && f.kind == kind)
    else {
        log::debug!("PCNET update: sem instalador p/ {}/{}/{}", platform, arch, kind);
        return Ok(());
    };

    // 4) baixar o instalador.
    let download_url = format!("{}/{}", PCNET_UPDATE_BASE, file.name);
    let data = client
        .get(&download_url)
        .send()?
        .error_for_status()?
        .bytes()?;

    // 5) verificar o sha256 contra o manifesto (assinado).
    {
        use sha2::{Digest, Sha256};
        let got = Sha256::digest(&data)
            .iter()
            .map(|b| format!("{:02x}", b))
            .collect::<String>();
        if got != file.sha256.to_lowercase() {
            bail!("PCNET update: sha256 do instalador nao corresponde ao manifesto");
        }
    }

    // 6) guardar e instalar.
    let Some(file_path) = get_download_file_from_url(&download_url) else {
        bail!("PCNET update: falha a obter o caminho de download de {}", download_url);
    };
    let mut f = std::fs::File::create(&file_path)?;
    f.write_all(&data)?;
    drop(f);
    // Reconfirmar que nao ha ligacoes activas antes de disparar o instalador.
    if has_no_active_conns() {
        log::info!("PCNET update: instalando {} -> {}", version, file.name);
        #[cfg(target_os = "windows")]
        update_new_version(update_msi, &version, &file_path);
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn update_new_version(update_msi: bool, version: &str, file_path: &PathBuf) {
    log::debug!(
        "New version is downloaded, update begin, update msi: {update_msi}, version: {version}, file: {:?}",
        file_path.to_str()
    );
    if let Some(p) = file_path.to_str() {
        if let Some(session_id) = crate::platform::get_current_process_session_id() {
            if update_msi {
                match crate::platform::update_me_msi(p, true) {
                    Ok(_) => {
                        log::debug!("New version \"{}\" updated.", version);
                    }
                    Err(e) => {
                        log::error!(
                            "Failed to install the new msi version  \"{}\": {}",
                            version,
                            e
                        );
                        std::fs::remove_file(&file_path).ok();
                    }
                }
            } else {
                let custom_client_staging_dir = if crate::is_custom_client() {
                    let custom_client_staging_dir =
                        crate::platform::get_custom_client_staging_dir();
                    if let Err(e) = crate::platform::handle_custom_client_staging_dir_before_update(
                        &custom_client_staging_dir,
                    ) {
                        log::error!(
                            "Failed to handle custom client staging dir before update: {}",
                            e
                        );
                        std::fs::remove_file(&file_path).ok();
                        return;
                    }
                    Some(custom_client_staging_dir)
                } else {
                    // Clean up any residual staging directory from previous custom client
                    let staging_dir = crate::platform::get_custom_client_staging_dir();
                    hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                        &staging_dir
                    ));
                    None
                };
                let update_launched = match crate::platform::launch_privileged_process(
                    session_id,
                    &format!("{} --update", p),
                ) {
                    Ok(h) => {
                        if h.is_null() {
                            log::error!("Failed to update to the new version: {}", version);
                            false
                        } else {
                            log::debug!("New version \"{}\" is launched.", version);
                            true
                        }
                    }
                    Err(e) => {
                        log::error!("Failed to run the new version: {}", e);
                        false
                    }
                };
                if !update_launched {
                    if let Some(dir) = custom_client_staging_dir {
                        hbb_common::allow_err!(crate::platform::remove_custom_client_staging_dir(
                            &dir
                        ));
                    }
                    std::fs::remove_file(&file_path).ok();
                }
            }
        } else {
            log::error!(
                "Failed to get the current process session id, Error {}",
                std::io::Error::last_os_error()
            );
            std::fs::remove_file(&file_path).ok();
        }
    } else {
        // unreachable!()
        log::error!(
            "Failed to convert the file path to string: {}",
            file_path.display()
        );
    }
}

pub fn get_download_file_from_url(url: &str) -> Option<PathBuf> {
    let filename = url.split('/').last()?;
    Some(std::env::temp_dir().join(filename))
}
