-- Portal DM CRM — esquema completo
-- Executar uma única vez no SQL Editor do Supabase.
-- É seguro voltar a executar: as tabelas usam IF NOT EXISTS e os dados iniciais usam ON CONFLICT.

create extension if not exists pgcrypto;

-- =========================================================
-- Funções comuns
-- =========================================================
create or replace function public.crm_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.crm_roles (
  id text primary key,
  name text not null unique,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.crm_permissions (
  id text primary key,
  module text not null,
  action text not null,
  description text,
  created_at timestamptz not null default now(),
  unique(module, action)
);

create table if not exists public.crm_role_permissions (
  role_id text not null references public.crm_roles(id) on update cascade on delete cascade,
  permission_id text not null references public.crm_permissions(id) on update cascade on delete cascade,
  allowed boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(role_id, permission_id)
);

-- Mantém IDs de texto para ser compatível com o login atual do Portal DM.
-- auth_user_id permite migrar mais tarde para Supabase Auth sem recriar os perfis.
create table if not exists public.crm_profiles (
  id text primary key,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  display_name text not null,
  email text,
  phone text,
  role text not null default 'comercial' references public.crm_roles(id) on update cascade,
  color text not null default '#0657ff',
  active boolean not null default true,
  permissions jsonb not null default '{}'::jsonb,
  preferences jsonb not null default '{}'::jsonb,
  last_login_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.crm_profile_permissions (
  profile_id text not null references public.crm_profiles(id) on update cascade on delete cascade,
  permission_id text not null references public.crm_permissions(id) on update cascade on delete cascade,
  allowed boolean not null,
  created_at timestamptz not null default now(),
  primary key(profile_id, permission_id)
);

create table if not exists public.crm_clients (
  id uuid primary key default gen_random_uuid(),
  source_key text unique,
  name text not null,
  nif text,
  district text,
  zone text,
  phone text,
  email text,
  owner_id text references public.crm_profiles(id) on update cascade on delete set null,
  owner_name text,
  notes text,
  extra_fields jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_by text references public.crm_profiles(id) on update cascade on delete set null,
  updated_by text references public.crm_profiles(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists crm_clients_name_idx on public.crm_clients using btree(name);
create index if not exists crm_clients_nif_idx on public.crm_clients using btree(nif);
create index if not exists crm_clients_owner_idx on public.crm_clients using btree(owner_id);

create table if not exists public.crm_contacts (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.crm_clients(id) on delete cascade,
  name text not null,
  job_title text,
  phone text,
  mobile text,
  email text,
  preferred_contact text,
  notes text,
  is_primary boolean not null default false,
  active boolean not null default true,
  created_by text references public.crm_profiles(id) on update cascade on delete set null,
  updated_by text references public.crm_profiles(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Catálogo de artigos proveniente das vendas. O CRM pode consultar/importar,
-- mas a interface não deve editar estes dados.
create table if not exists public.crm_products (
  id uuid primary key default gen_random_uuid(),
  source_key text unique,
  code text not null,
  description text,
  supplier text,
  business_area text,
  product_group text,
  family text,
  subfamily text,
  active boolean not null default true,
  source_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists crm_products_code_idx on public.crm_products using btree(code);

create table if not exists public.crm_opportunities (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  client_id uuid references public.crm_clients(id) on delete set null,
  contact_id uuid references public.crm_contacts(id) on delete set null,
  client_name text,
  value numeric(14,2) not null default 0,
  probability numeric(5,2) not null default 0 check (probability >= 0 and probability <= 100),
  status text not null default 'Novo',
  priority text not null default 'Normal',
  source text,
  owner_id text not null references public.crm_profiles(id) on update cascade,
  owner_name text,
  expected_close date,
  closed_at timestamptz,
  loss_reason text,
  notes text,
  extra_fields jsonb not null default '{}'::jsonb,
  created_by text references public.crm_profiles(id) on update cascade on delete set null,
  updated_by text references public.crm_profiles(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists crm_opportunities_owner_idx on public.crm_opportunities(owner_id);
create index if not exists crm_opportunities_status_idx on public.crm_opportunities(status);
create index if not exists crm_opportunities_client_idx on public.crm_opportunities(client_id);

create table if not exists public.crm_opportunity_items (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  product_id uuid references public.crm_products(id) on delete set null,
  product_code text,
  description text,
  quantity numeric(14,3) not null default 1,
  unit_price numeric(14,4) not null default 0,
  discount_percent numeric(6,3) not null default 0,
  total numeric(14,2) generated always as
    (round((quantity * unit_price * (1 - discount_percent / 100.0))::numeric, 2)) stored,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.crm_opportunity_history (
  id bigint generated always as identity primary key,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  previous_status text,
  new_status text,
  previous_owner_id text,
  new_owner_id text,
  changed_by text references public.crm_profiles(id) on update cascade on delete set null,
  notes text,
  changed_at timestamptz not null default now()
);

create table if not exists public.crm_activities (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid references public.crm_opportunities(id) on delete cascade,
  client_id uuid references public.crm_clients(id) on delete set null,
  contact_id uuid references public.crm_contacts(id) on delete set null,
  client_name text,
  type text not null,
  subject text not null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  owner_id text not null references public.crm_profiles(id) on update cascade,
  owner_name text,
  location text,
  notes text,
  completed boolean not null default false,
  completed_at timestamptz,
  reminder_minutes integer,
  extra_fields jsonb not null default '{}'::jsonb,
  created_by text references public.crm_profiles(id) on update cascade on delete set null,
  updated_by text references public.crm_profiles(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at)
);

create index if not exists crm_activities_owner_starts_idx on public.crm_activities(owner_id, starts_at);

create table if not exists public.crm_calendar_events (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid unique references public.crm_activities(id) on delete cascade,
  opportunity_id uuid references public.crm_opportunities(id) on delete cascade,
  client_id uuid references public.crm_clients(id) on delete set null,
  title text not null,
  event_type text not null default 'Evento',
  starts_at timestamptz not null,
  ends_at timestamptz,
  all_day boolean not null default false,
  location text,
  description text,
  owner_id text not null references public.crm_profiles(id) on update cascade,
  color text,
  completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at)
);

create table if not exists public.crm_alerts (
  id uuid primary key default gen_random_uuid(),
  owner_id text not null references public.crm_profiles(id) on update cascade on delete cascade,
  opportunity_id uuid references public.crm_opportunities(id) on delete cascade,
  activity_id uuid references public.crm_activities(id) on delete cascade,
  title text not null,
  message text,
  alert_type text not null default 'Lembrete',
  due_at timestamptz not null,
  read_at timestamptz,
  dismissed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists crm_alerts_owner_due_idx on public.crm_alerts(owner_id, due_at);

create table if not exists public.crm_assistance_tickets (
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.crm_clients(id) on delete set null,
  contact_id uuid references public.crm_contacts(id) on delete set null,
  opportunity_id uuid references public.crm_opportunities(id) on delete set null,
  subject text not null,
  description text,
  status text not null default 'Aberta',
  priority text not null default 'Normal',
  category text,
  requester_id text references public.crm_profiles(id) on update cascade on delete set null,
  assigned_to text references public.crm_profiles(id) on update cascade on delete set null,
  due_at timestamptz,
  resolved_at timestamptz,
  resolution text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.crm_comments (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid references public.crm_opportunities(id) on delete cascade,
  ticket_id uuid references public.crm_assistance_tickets(id) on delete cascade,
  activity_id uuid references public.crm_activities(id) on delete cascade,
  author_id text references public.crm_profiles(id) on update cascade on delete set null,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(opportunity_id, ticket_id, activity_id) = 1)
);

create table if not exists public.crm_attachments (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid references public.crm_opportunities(id) on delete cascade,
  ticket_id uuid references public.crm_assistance_tickets(id) on delete cascade,
  activity_id uuid references public.crm_activities(id) on delete cascade,
  client_id uuid references public.crm_clients(id) on delete cascade,
  file_name text not null,
  storage_bucket text not null default 'crm-attachments',
  storage_path text not null,
  mime_type text,
  size_bytes bigint,
  uploaded_by text references public.crm_profiles(id) on update cascade on delete set null,
  created_at timestamptz not null default now(),
  check (num_nonnulls(opportunity_id, ticket_id, activity_id, client_id) = 1)
);

-- Opções editáveis pela Assistência/Administração.
create table if not exists public.crm_lookup_values (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  value text not null,
  label text not null,
  color text,
  sort_order integer not null default 0,
  active boolean not null default true,
  system_value boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(category, value)
);

-- Compatibilidade direta com a versão atual do app.js.
create table if not exists public.crm_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_by text references public.crm_profiles(id) on update cascade on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.crm_audit_log (
  id bigint generated always as identity primary key,
  table_name text not null,
  record_id text,
  action text not null,
  changed_by text,
  old_data jsonb,
  new_data jsonb,
  changed_at timestamptz not null default now()
);

-- =========================================================
-- Dados iniciais
-- =========================================================
insert into public.crm_roles(id,name,description) values
 ('assistencia','Assistência','Gestão funcional do CRM, utilizadores, campos e assistências'),
 ('administrador','Administrador','Acesso total aos dados e configurações'),
 ('comercial','Comercial','Acesso ao próprio trabalho comercial')
on conflict (id) do update set name=excluded.name, description=excluded.description;

insert into public.crm_permissions(id,module,action,description) values
 ('clients.view','clients','view','Consultar clientes'),
 ('clients.create','clients','create','Criar clientes'),
 ('clients.edit','clients','edit','Editar clientes'),
 ('clients.deactivate','clients','deactivate','Desativar e reativar clientes'),
 ('opportunities.view','opportunities','view','Consultar oportunidades'),
 ('opportunities.create','opportunities','create','Criar oportunidades'),
 ('opportunities.edit','opportunities','edit','Editar oportunidades'),
 ('opportunities.delete','opportunities','delete','Eliminar oportunidades'),
 ('activities.manage','activities','manage','Gerir atividades e calendário'),
 ('assistance.manage','assistance','manage','Gerir assistências'),
 ('settings.manage','settings','manage','Gerir campos e preferências'),
 ('users.manage','users','manage','Gerir utilizadores e permissões'),
 ('audit.view','audit','view','Consultar histórico de alterações')
on conflict (id) do update set description=excluded.description;

insert into public.crm_role_permissions(role_id,permission_id,allowed)
select r.id, p.id,
  case
    when r.id in ('assistencia','administrador') then true
    when r.id='comercial' and p.id in (
      'clients.view','clients.create','clients.edit',
      'opportunities.view','opportunities.create','opportunities.edit','opportunities.delete',
      'activities.manage'
    ) then true
    else false
  end
from public.crm_roles r cross join public.crm_permissions p
on conflict (role_id,permission_id) do update set allowed=excluded.allowed;

insert into public.crm_profiles(id,display_name,role,color,permissions) values
 ('assistencia','Assistência','assistencia','#7c3aed','{}'),
 ('administrador','Administrador','administrador','#0657ff','{}'),
 ('comercial','Comercial','comercial','#00a651','{}'),
 ('rui_ferreira','Rui Ferreira','comercial','#ef2f78','{}'),
 ('joao_rebelo','João Rebelo','comercial','#ff9900','{}'),
 ('sandro_loureiro','Sandro Loureiro','comercial','#06b6d4','{}')
on conflict (id) do update set display_name=excluded.display_name, role=excluded.role, color=excluded.color;

insert into public.crm_settings(key,value,description) values
 ('statuses','["Novo","Enviada","Negociação","Perdida","Hot Deal","Pronta a faturar","Ganho"]','Colunas do Kanban'),
 ('priorities','["Baixa","Normal","Alta","Urgente"]','Prioridades disponíveis'),
 ('activity_types','["Telefonema","Email","Reunião","Visita","Tarefa","Assistência"]','Tipos de atividade'),
 ('loss_reasons','["Preço","Sem resposta","Concorrência","Prazo","Outro"]','Motivos de perda'),
 ('opportunity_sources','["Cliente existente","Contacto direto","Recomendação","Website","Campanha","Outro"]','Origens das oportunidades'),
 ('assistance_statuses','["Aberta","Em análise","A aguardar","Resolvida","Fechada"]','Estados de assistência'),
 ('assistance_categories','["Comercial","Produto","Entrega","Faturação","Técnica","Outra"]','Categorias de assistência'),
 ('reminders','{"Enviada":15,"Perdida":15,"Hot Deal":10,"Pronta a faturar":5}','Dias para lembretes automáticos'),
 ('crm_preferences','{"allow_client_delete":false,"client_deactivation":true,"articles_editable":false,"audit_enabled":true}','Regras gerais do CRM')
on conflict (key) do update set description=excluded.description;

insert into public.crm_lookup_values(category,value,label,color,sort_order,system_value)
select 'opportunity_status', x.value, x.value, x.color, x.ord, true
from (values
 ('Novo','#64748b',10),('Enviada','#0657ff',20),('Negociação','#ff9900',30),
 ('Perdida','#b91c1c',40),('Hot Deal','#ef2f78',50),
 ('Pronta a faturar','#7c3aed',60),('Ganho','#047857',70)
) as x(value,color,ord)
on conflict (category,value) do update set label=excluded.label,color=excluded.color,sort_order=excluded.sort_order;

-- =========================================================
-- Triggers de atualização e histórico
-- =========================================================
do $$
declare t text;
begin
  foreach t in array array[
    'crm_roles','crm_profiles','crm_clients','crm_contacts','crm_products',
    'crm_opportunities','crm_opportunity_items','crm_activities','crm_calendar_events',
    'crm_alerts','crm_assistance_tickets','crm_comments','crm_lookup_values','crm_settings'
  ] loop
    execute format('drop trigger if exists %I on public.%I', 'set_updated_at_'||t, t);
    execute format('create trigger %I before update on public.%I for each row execute function public.crm_set_updated_at()', 'set_updated_at_'||t, t);
  end loop;
end $$;

create or replace function public.crm_audit_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  old_json jsonb;
  new_json jsonb;
  rid text;
begin
  old_json := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end;
  new_json := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end;
  rid := coalesce(new_json->>'id', old_json->>'id', new_json->>'key', old_json->>'key');
  insert into public.crm_audit_log(table_name,record_id,action,old_data,new_data)
  values (tg_table_name,rid,tg_op,old_json,new_json);
  return coalesce(new,old);
end;
$$;

create or replace function public.crm_opportunity_history_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op='INSERT' or old.status is distinct from new.status or old.owner_id is distinct from new.owner_id then
    insert into public.crm_opportunity_history(
      opportunity_id, previous_status, new_status, previous_owner_id, new_owner_id
    ) values (
      new.id,
      case when tg_op='INSERT' then null else old.status end,
      new.status,
      case when tg_op='INSERT' then null else old.owner_id end,
      new.owner_id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists history_crm_opportunities on public.crm_opportunities;
create trigger history_crm_opportunities
after insert or update of status,owner_id on public.crm_opportunities
for each row execute function public.crm_opportunity_history_trigger();

do $$
declare t text;
begin
  foreach t in array array[
    'crm_profiles','crm_clients','crm_contacts','crm_opportunities','crm_opportunity_items',
    'crm_activities','crm_calendar_events','crm_alerts','crm_assistance_tickets',
    'crm_comments','crm_attachments','crm_lookup_values','crm_settings'
  ] loop
    execute format('drop trigger if exists %I on public.%I', 'audit_'||t, t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.crm_audit_trigger()', 'audit_'||t, t);
  end loop;
end $$;

-- =========================================================
-- Segurança inicial / compatibilidade
-- =========================================================
-- A aplicação atual reutiliza o login local do Portal DM e ainda não usa Supabase Auth.
-- Por isso, estas políticas permitem à publishable/anon key operar nas tabelas do CRM.
-- Depois da migração do login para Supabase Auth, devem ser substituídas por políticas
-- individuais baseadas em auth.uid(). Nunca usar service_role no GitHub Pages.

do $$
declare t text;
begin
  foreach t in array array[
    'crm_roles','crm_permissions','crm_role_permissions','crm_profiles','crm_profile_permissions',
    'crm_clients','crm_contacts','crm_products','crm_opportunities','crm_opportunity_items',
    'crm_opportunity_history','crm_activities','crm_calendar_events','crm_alerts',
    'crm_assistance_tickets','crm_comments','crm_attachments','crm_lookup_values','crm_settings'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t||'_initial_access', t);
    execute format('create policy %I on public.%I for all to anon using (true) with check (true)', t||'_initial_access', t);
  end loop;
end $$;

-- O histórico é apenas de leitura pela aplicação pública; os triggers gravam como SECURITY DEFINER.
alter table public.crm_audit_log enable row level security;
drop policy if exists crm_audit_log_initial_read on public.crm_audit_log;
create policy crm_audit_log_initial_read on public.crm_audit_log for select to anon using (true);

-- Permissões explícitas para a API REST.
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;

-- Fim do esquema.
