begin;

    create table account(
        id serial primary key,
        email varchar(255) not null
    );

    create function returns_account()
        returns account language sql stable
    as $$ select id, email from account; $$;

    insert into account(email)
    values
        ('aardvark@x.com');


    create role anon;
    grant usage on schema graphql to anon;
    grant select on account to anon;

    savepoint a;

    set local role anon;

    -- Should be visible
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            __typename
          }
        }
        $$)
    );

    -- Should show an entrypoint on Query for returnAccount
    select jsonb_pretty(
        graphql.resolve($$
            query IntrospectionQuery {
              __schema {
                queryType {
                  fields {
                    name
                  }
                }
              }
            }
        $$)
    );

    rollback to a;

    revoke select on account from anon;
    set local role anon;

    -- We should no longer see "Account" types after revoking access
    select jsonb_pretty(
        graphql.resolve($$
        {
          __type(name: "Account") {
            __typename
          }
        }
        $$)
    );

    -- We should no longer see returnAccount since it references an unknown return type "Account"
    select jsonb_pretty(
        graphql.resolve($$
            query IntrospectionQuery {
              __schema {
                queryType {
                  fields {
                    name
                  }
                }
              }
            }
        $$)
    );

rollback;
