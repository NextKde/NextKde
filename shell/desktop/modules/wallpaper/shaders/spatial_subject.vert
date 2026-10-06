VARYING vec2 subjectUv;

void MAIN()
{
    subjectUv = UV0;
    POSITION = MODELVIEWPROJECTION_MATRIX * vec4(VERTEX, 1.0);
}
