create or replace function graphql.build_delete(
    ast jsonb,
    variable_definitions jsonb = '[]',
    variables jsonb = '{}',
    parent_type text = null,
    parent_block_name text = null
)
    returns text
    language plpgsql
as $$
declare
    result text;

    block_name text = graphql.slug();

    field_rec graphql.field = f
        from
            graphql.field f
        where
            f.name = graphql.name_literal(ast) and f.meta_kind = 'Mutation.delete';

    at_most text = graphql.arg_clause('first',  (ast -> 'arguments'), variable_definitions, field_rec.entity);

    returning_clause text;

    filter_arg jsonb = graphql.get_arg_by_name('filter',  graphql.jsonb_coalesce((ast -> 'arguments'), '[]'));
    where_clause text = graphql.where_clause(filter_arg, field_rec.entity, block_name, variables, variable_definitions);

begin

    returning_clause = format(
        'jsonb_build_array(jsonb_build_object( %s ))',
        string_agg(
            format(
                '%L, %s',
                graphql.alias_or_name_literal(x.sel),
                case
                    when nf.column_name is not null then format('%I.%I', block_name, nf.column_name)
                    when nf.meta_kind = 'Function' then format('%I(%I)', nf.func, block_name)
                    when nf.name = '__typename' then format('%L', nf.type_)
                    when nf.local_columns is not null and nf.meta_kind = 'Relationship.toMany' then graphql.build_connection_query(
                        ast := x.sel,
                        variable_definitions := variable_definitions,
                        variables := variables,
                        parent_type := field_rec.type_,
                        parent_block_name := block_name
                    )
                    when nf.local_columns is not null and nf.meta_kind = 'Relationship.toOne' then graphql.build_node_query(
                        ast := x.sel,
                        variable_definitions := variable_definitions,
                        variables := variables,
                        parent_type := field_rec.type_,
                        parent_block_name := block_name
                    )
                    else graphql.exception_unknown_field(graphql.name_literal(x.sel), field_rec.type_)
                end
            ),
            ','
        )
    )
    from
        jsonb_array_elements(ast -> 'selectionSet' -> 'selections') x(sel)
        left join graphql.field nf
            on field_rec.type_ = nf.parent_type
            and graphql.name_literal(x.sel) = nf.name;


    result = format(
        'delete from %I as %I where %s returning %s;',
        field_rec.entity,
        block_name,
        where_clause,
        coalesce(returning_clause, 'null')
    );

    return result;
end;
$$;
